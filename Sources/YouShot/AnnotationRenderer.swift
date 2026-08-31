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

enum RectShape: String, CaseIterable, Identifiable {
    case rounded
    case ellipse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: return "圆角矩形"
        case .ellipse: return "椭圆"
        }
    }

    var symbolName: String {
        switch self {
        case .rounded: return "rectangle"
        case .ellipse: return "oval"
        }
    }
}

enum TextBackdrop: String, CaseIterable, Identifiable {
    case none
    case rounded
    case capsule
    case circle
    case banner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .rounded: return "圆角"
        case .capsule: return "胶囊"
        case .circle: return "圆形"
        case .banner: return "横幅"
        }
    }

    var symbolName: String {
        switch self {
        case .none: return "circle.slash"
        case .rounded: return "rectangle.fill"
        case .capsule: return "capsule.fill"
        case .circle: return "circle.fill"
        case .banner: return "rectangle.bottomhalf.filled"
        }
    }

    /// 能完整包住文字矩形的背景框（与文字同一坐标系）。
    func wrapRect(textRect: CGRect, fontSize: CGFloat) -> CGRect {
        guard self != .none else { return textRect }
        let pad = max(6, fontSize * 0.32)
        switch self {
        case .none:
            return textRect
        case .rounded:
            return textRect.insetBy(dx: -pad, dy: -pad)
        case .capsule:
            let vertical = pad
            let horizontal = textRect.height / 2 + vertical
            return textRect.insetBy(dx: -horizontal, dy: -vertical)
        case .circle:
            let side = hypot(textRect.width, textRect.height) + pad * 2
            return CGRect(
                x: textRect.midX - side / 2,
                y: textRect.midY - side / 2,
                width: side,
                height: side
            )
        case .banner:
            return textRect.insetBy(dx: -pad * 1.2, dy: -pad)
        }
    }

    func cornerRadius(for box: CGRect, fontSize: CGFloat) -> CGFloat {
        switch self {
        case .none:
            return 0
        case .rounded:
            return min(max(6, fontSize * 0.32), box.height / 2)
        case .capsule, .circle:
            return box.height / 2
        case .banner:
            return min(6, box.height / 3)
        }
    }
}

struct OverlayItem: Identifiable {
    let id: UUID
    let kind: OverlayKind
    var frame: CGRect
    let color: NSColor
    let lineWidth: CGFloat
    var text: String
    let fontSize: CGFloat
    let backdrop: TextBackdrop
    let backdropColor: NSColor

    enum OverlayKind {
        case roundedRect
        case ellipse
        case text
    }

    static func shape(_ kind: OverlayKind, frame: CGRect, color: NSColor, lineWidth: CGFloat) -> OverlayItem {
        OverlayItem(
            id: UUID(),
            kind: kind,
            frame: frame,
            color: color,
            lineWidth: lineWidth,
            text: "",
            fontSize: 0,
            backdrop: .none,
            backdropColor: .white
        )
    }

    static func text(
        at point: CGPoint,
        text: String,
        color: NSColor,
        fontSize: CGFloat,
        backdrop: TextBackdrop,
        backdropColor: NSColor
    ) -> OverlayItem {
        let size = (text as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: fontSize)])
        return OverlayItem(
            id: UUID(),
            kind: .text,
            frame: CGRect(origin: point, size: size),
            color: color,
            lineWidth: 0,
            text: text,
            fontSize: fontSize,
            backdrop: backdrop,
            backdropColor: backdropColor
        )
    }

    func visualRect() -> CGRect {
        switch kind {
        case .roundedRect, .ellipse:
            return frame
        case .text:
            let textRect = CGRect(
                origin: frame.origin,
                size: CGSize(width: max(frame.width, 8), height: max(frame.height, fontSize))
            )
            return backdrop.wrapRect(textRect: textRect, fontSize: fontSize)
        }
    }

    func draw(on image: CGImage) -> CGImage? {
        switch kind {
        case .roundedRect:
            return AnnotationRenderer.drawRect(on: image, rect: frame, color: color, lineWidth: lineWidth)
        case .ellipse:
            return AnnotationRenderer.drawEllipse(on: image, rect: frame, color: color, lineWidth: lineWidth)
        case .text:
            return AnnotationRenderer.drawText(
                on: image,
                text: text,
                at: frame.origin,
                color: color,
                fontSize: fontSize,
                backdrop: backdrop,
                backdropColor: backdropColor
            )
        }
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

    static var customIndex: Int { colors.count }

    static func color(at index: Int) -> NSColor {
        colors[min(max(index, 0), colors.count - 1)]
    }

    static func resolved(index: Int, customHex: String) -> NSColor {
        if index >= colors.count {
            return color(fromHex: customHex) ?? .systemRed
        }
        return color(at: index)
    }

    static func hex(from color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "FF3B30" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    static func color(fromHex hex: String) -> NSColor? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
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

    static func drawEllipse(
        on image: CGImage,
        rect: CGRect,
        color: NSColor = defaultColor,
        lineWidth: CGFloat = defaultLineWidth
    ) -> CGImage? {
        draw(on: image) { ctx, height in
            let r = bottomLeft(rect, height: height).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.strokeEllipse(in: r)
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
                let converted = bottomLeft(rect, height: height)
                let radius = highlightCornerRadius(for: rect)
                ctx.addPath(
                    CGPath(
                        roundedRect: converted,
                        cornerWidth: radius,
                        cornerHeight: radius,
                        transform: nil
                    )
                )
                ctx.fillPath()
            }
            ctx.setBlendMode(.normal)
            ctx.endTransparencyLayer()
        }
    }

    /// 高亮选区圆角（截图像素），小选区自动收紧，避免退化成胶囊形。
    static func highlightCornerRadius(for rect: CGRect) -> CGFloat {
        min(12, min(rect.width, rect.height) / 4)
    }

    static func drawText(
        on image: CGImage,
        text: String,
        at point: CGPoint,
        color: NSColor = defaultColor,
        fontSize: CGFloat = 28,
        backdrop: TextBackdrop = .none,
        backdropColor: NSColor = .white
    ) -> CGImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return image }
        return drawWithAppKit(on: image) { size in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: color,
            ]
            let string = trimmed as NSString
            let textSize = string.size(withAttributes: attrs)
            let origin = NSPoint(x: point.x, y: size.height - point.y - textSize.height)
            fillTextBackdrop(
                backdrop,
                color: backdropColor,
                textOrigin: origin,
                textSize: textSize,
                fontSize: fontSize
            )
            string.draw(at: origin, withAttributes: attrs)
        }
    }

    private static func fillTextBackdrop(
        _ backdrop: TextBackdrop,
        color: NSColor,
        textOrigin: NSPoint,
        textSize: CGSize,
        fontSize: CGFloat
    ) {
        guard backdrop != .none else { return }
        let textRect = CGRect(origin: textOrigin, size: textSize)
        let box = backdrop.wrapRect(textRect: textRect, fontSize: fontSize)
        let radius = backdrop.cornerRadius(for: box, fontSize: fontSize)
        color.setFill()
        switch backdrop {
        case .none:
            break
        case .circle:
            NSBezierPath(ovalIn: box).fill()
        case .rounded, .capsule, .banner:
            NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
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
