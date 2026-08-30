import AppKit
import CoreGraphics
import CoreImage

enum EditorTool: String, CaseIterable, Identifiable {
    case rect
    case line
    case arrow
    case pen
    case text
    case highlight
    case mosaic
    case blur
    case watermark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rect: return "矩形"
        case .line: return "直线"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .text: return "文字"
        case .highlight: return "高亮"
        case .mosaic: return "马赛克"
        case .blur: return "模糊"
        case .watermark: return "水印"
        }
    }

    var symbolName: String {
        switch self {
        case .rect: return "rectangle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .highlight: return "sun.max.fill"
        case .mosaic: return "square.grid.3x3.fill"
        case .blur: return "drop.fill"
        case .watermark: return "signature"
        }
    }

}

enum PenBrush: String, CaseIterable, Identifiable {
    case hard
    case highlighter
    case soft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hard: return "硬笔"
        case .highlighter: return "荧光笔"
        case .soft: return "柔边"
        }
    }

    var symbolName: String {
        switch self {
        case .hard: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .soft: return "paintbrush.pointed"
        }
    }

    /// 荧光笔略宽，更接近马克笔。
    var widthScale: CGFloat {
        self == .highlighter ? 1.8 : 1
    }
}

enum WatermarkStyle: String, CaseIterable, Identifiable {
    case tile
    case center
    case corner
    case banner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tile: return "斜向平铺"
        case .center: return "居中大字"
        case .corner: return "右下角"
        case .banner: return "底部横幅"
        }
    }
}

enum AnnotationPalette {
    static let colors: [NSColor] = [
        .systemRed,
        .systemOrange,
        .systemYellow,
        .systemGreen,
        .systemBlue,
        .systemPurple,
        .white,
        .black,
    ]

    static func color(at index: Int) -> NSColor {
        colors[min(max(index, 0), colors.count - 1)]
    }
}

enum AnnotationRenderer {
    static let defaultColor = NSColor.systemRed
    static let defaultLineWidth: CGFloat = 4
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func drawRect(on image: CGImage, rect: CGRect, color: NSColor = defaultColor, lineWidth: CGFloat = defaultLineWidth) -> CGImage? {
        draw(on: image) { ctx, height in
            let r = bottomLeft(rect, height: height).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let radius = rectCornerRadius(for: r, lineWidth: lineWidth)
            let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    static func drawLine(
        on image: CGImage,
        from: CGPoint,
        to: CGPoint,
        color: NSColor = defaultColor,
        lineWidth: CGFloat = defaultLineWidth
    ) -> CGImage? {
        draw(on: image) { ctx, height in
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: bottomLeftPoint(from, height: height))
            ctx.addLine(to: bottomLeftPoint(to, height: height))
            ctx.strokePath()
        }
    }

    /// 矩形圆角：随边长与线宽变化，避免小框变成椭圆。
    static func rectCornerRadius(for rect: CGRect, lineWidth: CGFloat) -> CGFloat {
        let limit = min(rect.width, rect.height) / 4
        return min(limit, max(lineWidth * 2.5, 8))
    }

    static func drawArrow(
        on image: CGImage,
        from: CGPoint,
        to: CGPoint,
        color: NSColor = defaultColor,
        lineWidth: CGFloat = defaultLineWidth
    ) -> CGImage? {
        draw(on: image) { ctx, height in
            ctx.setFillColor(color.cgColor)
            ctx.addPath(
                arrowPath(
                    from: bottomLeftPoint(from, height: height),
                    to: bottomLeftPoint(to, height: height),
                    lineWidth: lineWidth
                )
            )
            ctx.fillPath()
        }
    }

    /// 圆润箭头：尾部收窄的曲线杆身 + 弧边箭头，预览与输出共用同一条路径。
    static func arrowPath(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat) -> CGPath {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        let width = max(lineWidth, 1)
        let head = min(length * 0.55, width * 5.5)
        let neck = length - head
        let headHalf = width * 2.6
        let bodyHalf = width * 0.55
        let tailHalf = bodyHalf * 0.4
        let barbX = neck - head * 0.05

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: tailHalf))
        path.addQuadCurve(
            to: CGPoint(x: neck, y: bodyHalf),
            control: CGPoint(x: neck * 0.55, y: bodyHalf * 0.7)
        )
        path.addQuadCurve(
            to: CGPoint(x: barbX, y: headHalf),
            control: CGPoint(x: neck + head * 0.01, y: bodyHalf * 1.9)
        )
        path.addQuadCurve(
            to: CGPoint(x: length, y: 0),
            control: CGPoint(x: neck + head * 0.55, y: headHalf * 0.42)
        )
        path.addQuadCurve(
            to: CGPoint(x: barbX, y: -headHalf),
            control: CGPoint(x: neck + head * 0.55, y: -headHalf * 0.42)
        )
        path.addQuadCurve(
            to: CGPoint(x: neck, y: -bodyHalf),
            control: CGPoint(x: neck + head * 0.01, y: -bodyHalf * 1.9)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: -tailHalf),
            control: CGPoint(x: neck * 0.55, y: -bodyHalf * 0.7)
        )
        path.addQuadCurve(
            to: CGPoint(x: 0, y: tailHalf),
            control: CGPoint(x: -tailHalf * 1.8, y: 0)
        )
        path.closeSubpath()

        var transform = CGAffineTransform(translationX: start.x, y: start.y)
            .rotated(by: atan2(dy, dx))
        return path.copy(using: &transform) ?? path
    }

    static func drawPen(
        on image: CGImage,
        points: [CGPoint],
        color: NSColor = defaultColor,
        lineWidth: CGFloat = defaultLineWidth,
        brush: PenBrush = .hard,
        opacity: CGFloat = 1
    ) -> CGImage? {
        guard points.count >= 2 else { return image }
        let width = max(1, lineWidth * brush.widthScale)
        let paint = color.withAlphaComponent(min(max(opacity, 0.05), 1))
        if brush == .soft {
            return drawSoftPen(on: image, points: points, color: paint, lineWidth: width)
        }
        return draw(on: image) { ctx, height in
            if brush == .highlighter {
                ctx.setBlendMode(.multiply)
            }
            strokePenPath(in: ctx, points: points, height: height, color: paint, lineWidth: width)
        }
    }

    private static func strokePenPath(
        in ctx: CGContext,
        points: [CGPoint],
        height: CGFloat,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: bottomLeftPoint(points[0], height: height))
        for point in points.dropFirst() {
            ctx.addLine(to: bottomLeftPoint(point, height: height))
        }
        ctx.strokePath()
    }

    /// 先画到透明层再高斯模糊，得到柔边笔刷。
    private static func drawSoftPen(
        on image: CGImage,
        points: [CGPoint],
        color: NSColor,
        lineWidth: CGFloat
    ) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let strokeCtx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return image
        }
        strokePenPath(
            in: strokeCtx,
            points: points,
            height: CGFloat(height),
            color: color,
            lineWidth: lineWidth
        )
        guard let strokeImage = strokeCtx.makeImage() else { return image }
        let input = CIImage(cgImage: strokeImage)
        let sigma = max(0.6, lineWidth * 0.45)
        let blurred = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: input.extent)
        guard let blurredCG = ciContext.createCGImage(blurred, from: input.extent) else { return image }
        return draw(on: image) { ctx, _ in
            ctx.draw(blurredCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 高亮：所有区域共用一层遮罩，重叠部分不会加深。
    static func drawHighlight(on image: CGImage, rects: [CGRect], dim: CGFloat) -> CGImage? {
        guard !rects.isEmpty else { return image }
        return draw(on: image) { ctx, height in
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setFillColor(CGColor(gray: 0, alpha: min(max(dim, 0), 1)))
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(image.width), height: height))
            ctx.setBlendMode(.clear)
            for rect in rects {
                ctx.fill(bottomLeft(rect, height: height))
            }
            ctx.setBlendMode(.normal)
            ctx.endTransparencyLayer()
        }
    }

    static func drawText(
        on image: CGImage,
        text: String,
        at point: CGPoint,
        color: NSColor = defaultColor,
        fontSize: CGFloat = 28
    ) -> CGImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return image }
        return drawWithAppKit(on: image) { size in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: color,
            ]
            (trimmed as NSString).draw(
                at: NSPoint(x: point.x, y: size.height - point.y - fontSize),
                withAttributes: attrs
            )
        }
    }

    /// 水印：按预设样式叠在整张截图上。`scale` 为点到像素的倍率，`fontSize` 已含倍率。
    static func drawWatermark(
        on image: CGImage,
        text: String,
        style: WatermarkStyle,
        scale: CGFloat,
        fontSize: CGFloat,
        color: NSColor,
        opacity: CGFloat
    ) -> CGImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return image }
        let string = trimmed as NSString
        let alpha = min(max(opacity, 0.02), 1)
        let sizePx = max(8, fontSize)
        return drawWithAppKit(on: image) { size in
            switch style {
            case .tile:
                let attrs = watermarkAttributes(fontSize: sizePx, color: color, alpha: alpha)
                let textSize = string.size(withAttributes: attrs)
                let stepX = textSize.width + 70 * scale
                let stepY = textSize.height + 70 * scale
                let reach = hypot(size.width, size.height)
                NSGraphicsContext.saveGraphicsState()
                let rotation = NSAffineTransform()
                rotation.rotate(byDegrees: -22)
                rotation.concat()
                var y = -reach
                while y < reach {
                    var x = -reach
                    while x < reach {
                        string.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                        x += stepX
                    }
                    y += stepY
                }
                NSGraphicsContext.restoreGraphicsState()
            case .center:
                let attrs = watermarkAttributes(fontSize: sizePx, color: color, alpha: alpha)
                let textSize = string.size(withAttributes: attrs)
                string.draw(
                    at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                    withAttributes: attrs
                )
            case .corner:
                let attrs = watermarkAttributes(fontSize: sizePx, color: color, alpha: alpha)
                let textSize = string.size(withAttributes: attrs)
                let pad = 12 * scale
                string.draw(
                    at: NSPoint(x: size.width - textSize.width - pad, y: pad),
                    withAttributes: attrs
                )
            case .banner:
                let attrs = watermarkAttributes(fontSize: sizePx, color: color, alpha: alpha)
                let textSize = string.size(withAttributes: attrs)
                let barHeight = textSize.height + 14 * scale
                NSColor.black.withAlphaComponent(min(0.55, alpha * 1.4)).setFill()
                NSRect(x: 0, y: 0, width: size.width, height: barHeight).fill()
                string.draw(
                    at: NSPoint(x: (size.width - textSize.width) / 2, y: (barHeight - textSize.height) / 2),
                    withAttributes: attrs
                )
            }
        }
    }

    private static func watermarkAttributes(fontSize: CGFloat, color: NSColor, alpha: CGFloat) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(alpha * 0.7)
        shadow.shadowBlurRadius = max(1, fontSize * 0.12)
        return [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: color.withAlphaComponent(alpha),
            .shadow: shadow,
        ]
    }

    /// 在截图像素画布上用 AppKit 绘制（左下原点）。
    private static func drawWithAppKit(on image: CGImage, body: (NSSize) -> Void) -> CGImage? {
        draw(on: image) { ctx, _ in
            let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            body(NSSize(width: image.width, height: image.height))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func draw(on image: CGImage, body: (CGContext, CGFloat) -> Void) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        body(ctx, CGFloat(height))
        return ctx.makeImage()
    }

    private static func bottomLeft(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func bottomLeftPoint(_ point: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: height - point.y)
    }
}
