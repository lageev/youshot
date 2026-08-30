import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum ImageRedact {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func applyMosaic(to image: CGImage, rect: CGRect, blockSize: Int = 14) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixelRect = rect.integral.intersection(bounds)
        guard pixelRect.width >= 2, pixelRect.height >= 2 else { return image }
        guard let cropped = image.cropping(to: pixelRect) else { return image }

        let tinyW = max(1, Int(pixelRect.width) / blockSize)
        let tinyH = max(1, Int(pixelRect.height) / blockSize)
        guard let tiny = resize(cropped, width: tinyW, height: tinyH) else { return image }
        guard let mosaic = resize(tiny, width: Int(pixelRect.width), height: Int(pixelRect.height)) else {
            return image
        }

        guard let context = makeRGBContext(width: image.width, height: image.height, colorSpace: image.colorSpace) else {
            return image
        }
        context.interpolationQuality = .none
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: full)
        context.draw(mosaic, in: bottomLeftRect(pixelRect, imageHeight: CGFloat(image.height)))
        return context.makeImage()
    }

    /// 对选区做高斯模糊；选区内完全遮挡，羽化只向外溢出。
    static func applyBlur(
        to image: CGImage,
        rect: CGRect,
        sigma: CGFloat,
        feather: CGFloat
    ) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixelRect = rect.intersection(bounds)
        guard pixelRect.width >= 2, pixelRect.height >= 2 else { return image }

        let blurSigma = max(0.5, sigma)
        let featherWidth = max(0, feather)

        let ciInput = CIImage(cgImage: image)
        let extent = ciInput.extent

        // 整图模糊（clamp 避免边缘发黑），再靠柔和蒙版决定哪里显示模糊
        let blurred = ciInput
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurSigma)
            .cropped(to: extent)

        guard let mask = outwardFeatherMask(
            width: image.width,
            height: image.height,
            topLeftRect: pixelRect,
            feather: featherWidth
        ) else {
            return image
        }

        let output = blurred.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: ciInput,
                kCIInputMaskImageKey: mask,
            ]
        )

        return ciContext.createCGImage(output, from: extent)
    }

    /// 距离场蒙版（与截图像素同为左上原点）：选区内 = 1；外侧 feather 内平滑降到 0。
    private static func outwardFeatherMask(
        width: Int,
        height: Int,
        topLeftRect: CGRect,
        feather: CGFloat
    ) -> CIImage? {
        let rect = topLeftRect
        let bytesPerRow = width
        var pixels = [UInt8](repeating: 0, count: width * height)

        let pad = Int(ceil(feather)) + 1
        let minX = max(0, Int(floor(rect.minX)) - pad)
        let maxX = min(width - 1, Int(ceil(rect.maxX)) + pad)
        let minY = max(0, Int(floor(rect.minY)) - pad)
        let maxY = min(height - 1, Int(ceil(rect.maxY)) + pad)
        guard minX <= maxX, minY <= maxY else { return nil }

        for y in minY...maxY {
            for x in minX...maxX {
                let px = CGFloat(x) + 0.5
                let py = CGFloat(y) + 0.5
                let alpha: CGFloat
                if px >= rect.minX, px < rect.maxX, py >= rect.minY, py < rect.maxY {
                    alpha = 1
                } else {
                    let dx = max(rect.minX - px, 0, px - rect.maxX)
                    let dy = max(rect.minY - py, 0, py - rect.maxY)
                    let dist = hypot(dx, dy)
                    if dist >= feather {
                        alpha = 0
                    } else {
                        let t = 1 - dist / feather
                        alpha = t * t * (3 - 2 * t) // smoothstep
                    }
                }
                pixels[y * bytesPerRow + x] = UInt8(clamping: Int((alpha * 255).rounded()))
            }
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        guard let cgMask = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        // CGImage 数据为顶下行优先；与 CIImage(cgImage:) 的截图坐标系对齐
        return CIImage(cgImage: cgMask)
    }

    private static func bottomLeftRect(_ topLeft: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(
            x: topLeft.minX,
            y: imageHeight - topLeft.maxY,
            width: topLeft.width,
            height: topLeft.height
        )
    }

    private static func makeGrayContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
    }

    private static func makeRGBContext(width: Int, height: Int, colorSpace: CGColorSpace?) -> CGContext? {
        let space = colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: bitmapInfo.rawValue
        )
    }

    private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = makeRGBContext(width: width, height: height, colorSpace: image.colorSpace) else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

enum ImageExportStyle {
    static func apply(
        _ image: CGImage,
        cornerRadius: CGFloat,
        shadowBlur: CGFloat,
        shadowOpacity: CGFloat,
        shadowOffsetY: CGFloat
    ) -> CGImage? {
        let maxRadius = CGFloat(min(image.width, image.height)) / 2
        let radius = min(max(0, cornerRadius), maxRadius)
        let blur = max(0, shadowBlur)
        let opacity = min(max(0, shadowOpacity), 1)
        let offsetY = max(0, shadowOffsetY)
        let hasShadow = blur > 0.5 && opacity > 0.01
        let hasCorner = radius > 0.5
        if !hasShadow && !hasCorner {
            return image
        }

        let pad = hasShadow ? ceil(blur * 1.35) : 0
        let padX = Int(pad)
        let padTop = Int(pad)
        let padBottom = Int(pad + (hasShadow ? ceil(offsetY) : 0))
        let canvasW = image.width + padX * 2
        let canvasH = image.height + padTop + padBottom
        // RGBA + premultipliedLast，便于写出真正带透明通道的 PNG
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: canvasW,
            height: canvasH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }

        context.clear(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        let imageRect = CGRect(
            x: CGFloat(padX),
            y: CGFloat(padBottom),
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        )
        let path: CGPath
        if hasCorner {
            path = CGPath(
                roundedRect: imageRect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        } else {
            path = CGPath(rect: imageRect, transform: nil)
        }

        // 只绘制一次：阴影由图片自身的透明层投射，避免边缘重复合成出深边
        context.saveGState()
        if hasShadow {
            context.setShadow(
                offset: CGSize(width: 0, height: -offsetY),
                blur: blur,
                color: CGColor(gray: 0, alpha: opacity)
            )
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(image, in: imageRect)
        context.restoreGState()
        if hasShadow {
            context.endTransparencyLayer()
        }
        context.restoreGState()
        return context.makeImage()
    }
}

enum PNGFile {
    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw PNGWriteError.failed
        }
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .premultipliedLast, .premultipliedFirst, .first, .last, .alphaOnly:
            hasAlpha = true
        default:
            hasAlpha = false
        }
        // 有透明通道时强制声明，避免被写成不透明黑底
        var props: [CFString: Any] = [:]
        if hasAlpha {
            props[kCGImagePropertyHasAlpha] = true
            props[kCGImagePropertyPNGDictionary] = [
                kCGImagePropertyPNGInterlaceType: 0
            ]
        } else {
            props[kCGImagePropertyHasAlpha] = false
        }
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PNGWriteError.failed
        }
    }
}

enum PNGWriteError: LocalizedError {
    case failed

    var errorDescription: String? { "保存 PNG 失败" }
}

extension NSImage {
    var youshotCGImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    convenience init(youshotCGImage image: CGImage) {
        self.init(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
