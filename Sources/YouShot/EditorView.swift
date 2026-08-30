import AppKit
import SwiftUI

// MARK: - Toolbar

struct FloatingAnnotateToolbar: View {
    @EnvironmentObject private var controller: CaptureController

    var body: some View {
        VStack(spacing: 8) {
            styleBar

            HStack(spacing: 4) {
                ForEach(EditorTool.allCases) { item in
                    toolButton(item)
                }

                toolbarDivider

                iconButton("arrow.uturn.backward", enabled: controller.canUndoEditor) { controller.undoEditor() }
                iconButton("arrow.uturn.forward", enabled: controller.canRedoEditor) { controller.redoEditor() }
                iconButton("square.and.arrow.down", enabled: true) { controller.saveEditor() }

                toolbarDivider

                Button { controller.cancelEditor() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .help("取消")

                Button { controller.confirmEditor() } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, .green)
                }
                .buttonStyle(.plain)
                .help("完成")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background { barBackground }
        }
    }

    @ViewBuilder
    private var styleBar: some View {
        let tool = controller.editorTool
        if tool != .mosaic {
            HStack(spacing: 12) {
                switch tool {
                case .highlight:
                    miniSlider("遮罩", value: $controller.highlightDim, range: 0.1...0.9, step: 0.05, percent: true)
                case .blur:
                    miniSlider("强度", value: $controller.blurSigma, range: 4...40)
                    miniSlider("羽化", value: $controller.blurFeather, range: 0...120)
                case .watermark:
                    watermarkControls
                case .pen:
                    penControls
                default:
                    colorSwatches(index: $controller.strokeColorIndex)
                    miniSlider("粗细", value: $controller.strokeWidth, range: 1...16, width: 80)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background { barBackground }
        }
    }

    @ViewBuilder
    private var penControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                colorSwatches(index: $controller.strokeColorIndex)
                penBrushPicker
            }
            HStack(spacing: 10) {
                miniSlider("粗细", value: $controller.strokeWidth, range: 1...16, width: 80)
                miniSlider("透明", value: $controller.strokeOpacity, range: 0.05...1, step: 0.05, percent: true, width: 72)
            }
        }
    }

    private var penBrushPicker: some View {
        HStack(spacing: 4) {
            ForEach(PenBrush.allCases) { brush in
                let selected = controller.penBrush == brush
                Button {
                    controller.penBrush = brush
                } label: {
                    Image(systemName: brush.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(brush.title)
            }
        }
    }

    @ViewBuilder
    private var watermarkControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("水印文字", text: $controller.watermarkText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Picker("", selection: $controller.watermarkStyle) {
                    ForEach(WatermarkStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                Button("应用") { controller.applyWatermark() }
                    .disabled(controller.watermarkText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 10) {
                colorSwatches(index: $controller.watermarkColorIndex)
                miniSlider("大小", value: $controller.watermarkFontSize, range: 8...48, width: 72)
                miniSlider("透明", value: $controller.watermarkOpacity, range: 0.05...1, step: 0.05, percent: true, width: 72)
            }
        }
    }

    private func colorSwatches(index: Binding<Int>) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(AnnotationPalette.colors.enumerated()), id: \.offset) { offset, color in
                Button {
                    index.wrappedValue = offset
                } label: {
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                        .overlay {
                            if index.wrappedValue == offset {
                                Circle()
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .padding(-3)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var barBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.thickMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.86))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 6)
    }

    private func toolButton(_ item: EditorTool) -> some View {
        let selected = controller.editorTool == item
        return Button {
            controller.editorTool = item
        } label: {
            Group {
                if item == .text {
                    Text("T")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                } else if item == .watermark {
                    Text("水印")
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Image(systemName: item.symbolName)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(width: item == .watermark ? 40 : 32, height: 28)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(item == .pen || item == .line || item == .arrow ? "\(item.title)（按住 ⇧ 画直线）" : item.title)
    }

    private func iconButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func miniSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        percent: Bool = false,
        width: CGFloat = 110
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            // 保留步进值，但不用会自动展示底部刻度的 `step:` 初始化器。
            Slider(value: snappedBinding(value, range: range, step: step), in: range)
                .frame(width: width)
            Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue))")
                .font(.caption.monospacedDigit())
                .frame(width: percent ? 34 : 28, alignment: .trailing)
        }
    }

    private func snappedBinding(
        _ value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue },
            set: { proposed in
                let snapped = ((proposed - range.lowerBound) / step).rounded() * step + range.lowerBound
                value.wrappedValue = min(max(snapped, range.lowerBound), range.upperBound)
            }
        )
    }
}

// MARK: - Canvas（按截图区域实际点尺寸展示）

struct AnnotationCanvas: View {
    let image: NSImage
    let canvasSize: CGSize

    @EnvironmentObject private var controller: CaptureController
    @StateObject private var drag = DragState()

    private var tool: EditorTool { controller.editorTool }
    private var strokeColor: Color { Color(nsColor: controller.annotationColor) }
    private var strokeWidth: CGFloat { max(1, CGFloat(controller.strokeWidth)) }
    private var penStrokeColor: Color { strokeColor.opacity(controller.strokeOpacity) }
    private var penStrokeWidth: CGFloat { max(1, strokeWidth * controller.penBrush.widthScale) }

    var body: some View {
        let fitted = CGRect(origin: .zero, size: canvasSize)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .overlay {
                        Rectangle()
                            .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                    }

                highlightLayer(fitted: fitted)
                previewOverlay(fitted: fitted)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(fitted: fitted))

            inlineTextEditor(fitted: fitted)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    @ViewBuilder
    private func previewOverlay(fitted: CGRect) -> some View {
        switch tool {
        case .pen:
            if drag.points.count > 1 {
                let path = Path { path in
                    path.move(to: drag.points[0])
                    for p in drag.points.dropFirst() { path.addLine(to: p) }
                }
                let stroke = path.stroke(
                    penStrokeColor,
                    style: StrokeStyle(lineWidth: penStrokeWidth, lineCap: .round, lineJoin: .round)
                )
                switch controller.penBrush {
                case .hard:
                    stroke
                case .highlighter:
                    stroke.blendMode(.multiply)
                case .soft:
                    stroke.blur(radius: max(0.6, penStrokeWidth * 0.35))
                }
            }
        case .line:
            if let start = drag.start, let current = drag.current {
                Path { path in
                    path.move(to: start)
                    path.addLine(to: current)
                }
                .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
            }
        case .arrow:
            if let start = drag.start, let current = drag.current {
                Path(AnnotationRenderer.arrowPath(from: start, to: current, lineWidth: strokeWidth))
                    .fill(strokeColor)
            }
        case .rect:
            if let rect = previewRect(fitted: fitted) {
                let radius = AnnotationRenderer.rectCornerRadius(for: rect, lineWidth: strokeWidth)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: strokeWidth)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        case .mosaic, .blur:
            if let rect = previewRect(fitted: fitted) {
                let color: Color = tool == .blur ? .cyan : .yellow
                let radius = AnnotationRenderer.rectCornerRadius(for: rect, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(color, lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color.opacity(0.12)))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        case .text, .highlight, .watermark:
            EmptyView()
        }
    }

    /// 所有高亮区域共用一层遮罩，透明度跟着设置实时变化，重叠也不会加深。
    @ViewBuilder
    private func highlightLayer(fitted: CGRect) -> some View {
        let holes = highlightHoles(fitted: fitted)
        if !holes.isEmpty {
            Color.black.opacity(controller.highlightDim)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .mask {
                    Rectangle()
                        .fill(.white)
                        .overlay(alignment: .topLeading) {
                            ForEach(Array(holes.enumerated()), id: \.offset) { _, hole in
                                Rectangle()
                                    .frame(width: hole.width, height: hole.height)
                                    .offset(x: hole.minX, y: hole.minY)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                }
                .allowsHitTesting(false)
        }
    }

    private func highlightHoles(fitted: CGRect) -> [CGRect] {
        var holes = controller.highlightRects.compactMap { toViewRect($0, fitted: fitted) }
        if tool == .highlight, let rect = previewRect(fitted: fitted) {
            holes.append(rect)
        }
        return holes
    }

    /// 在点击位置直接键入文字，回车确认、Esc 取消。
    @ViewBuilder
    private func inlineTextEditor(fitted: CGRect) -> some View {
        if controller.showTextInput,
           let pixel = controller.pendingTextPoint,
           let origin = toView(pixel, fitted: fitted) {
            InlineTextField(
                origin: origin,
                available: max(60, canvasSize.width - origin.x - 6)
            )
        }
    }

    private func previewRect(fitted: CGRect) -> CGRect? {
        guard let start = drag.start, let current = drag.current else { return nil }
        return normalized(start, current).intersection(fitted)
    }

    private func dragGesture(fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: tool == .text ? 0 : 2)
            .onChanged { value in
                if tool == .text || tool == .watermark { return }
                if drag.start == nil {
                    drag.start = value.startLocation
                    drag.points = [value.startLocation]
                }
                let start = drag.start ?? value.startLocation
                let current = straightLockedEnd(from: start, to: value.location)
                drag.current = current
                if tool == .pen {
                    if Self.shiftHeld {
                        drag.points = [start, current]
                    } else {
                        drag.points.append(value.location)
                    }
                }
            }
            .onEnded { value in
                if tool == .text {
                    if let pixel = toPixel(value.startLocation, fitted: fitted) {
                        controller.beginTextInput(at: pixel)
                    }
                    drag.reset()
                    return
                }

                let start = drag.start ?? value.startLocation
                let end = straightLockedEnd(from: start, to: value.location)
                let points = Self.shiftHeld ? [start, end] : drag.points
                drag.reset()

                switch tool {
                case .rect:
                    if let rect = pixelRect(from: start, to: end, fitted: fitted) {
                        controller.applyRect(pixelRect: rect)
                    }
                case .line:
                    if let a = toPixel(start, fitted: fitted), let b = toPixel(end, fitted: fitted) {
                        controller.applyLine(from: a, to: b)
                    }
                case .arrow:
                    if let a = toPixel(start, fitted: fitted), let b = toPixel(end, fitted: fitted) {
                        controller.applyArrow(from: a, to: b)
                    }
                case .pen:
                    let pixelPoints = points.compactMap { toPixel($0, fitted: fitted) }
                    if pixelPoints.count >= 2 {
                        controller.applyPen(points: pixelPoints)
                    }
                case .highlight, .mosaic, .blur:
                    if let rect = pixelRect(from: start, to: end, fitted: fitted) {
                        controller.applyRedact(pixelRect: rect)
                    }
                case .text, .watermark:
                    break
                }
            }
    }

    /// 按住 ⇧ 时，画笔 / 直线 / 箭头吸附到水平、垂直或 45°。
    private func straightLockedEnd(from start: CGPoint, to current: CGPoint) -> CGPoint {
        guard Self.shiftHeld, tool == .pen || tool == .line || tool == .arrow else { return current }
        let dx = current.x - start.x
        let dy = current.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return current }
        let step = CGFloat.pi / 4
        let snapped = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: start.x + cos(snapped) * length, y: start.y + sin(snapped) * length)
    }

    private static var shiftHeld: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }

    private func normalized(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    private func pixelRect(from start: CGPoint, to end: CGPoint, fitted: CGRect) -> CGRect? {
        guard let cg = image.youshotCGImage else { return nil }
        let viewRect = normalized(start, end).intersection(fitted)
        guard viewRect.width >= 2, viewRect.height >= 2 else { return nil }
        let scaleX = CGFloat(cg.width) / fitted.width
        let scaleY = CGFloat(cg.height) / fitted.height
        return CGRect(
            x: (viewRect.minX - fitted.minX) * scaleX,
            y: (viewRect.minY - fitted.minY) * scaleY,
            width: viewRect.width * scaleX,
            height: viewRect.height * scaleY
        )
    }

    private func toPixel(_ point: CGPoint, fitted: CGRect) -> CGPoint? {
        guard fitted.contains(point), let cg = image.youshotCGImage else { return nil }
        let scaleX = CGFloat(cg.width) / fitted.width
        let scaleY = CGFloat(cg.height) / fitted.height
        return CGPoint(
            x: (point.x - fitted.minX) * scaleX,
            y: (point.y - fitted.minY) * scaleY
        )
    }

    private func toView(_ pixel: CGPoint, fitted: CGRect) -> CGPoint? {
        guard let cg = image.youshotCGImage, cg.width > 0, cg.height > 0 else { return nil }
        return CGPoint(
            x: fitted.minX + pixel.x * fitted.width / CGFloat(cg.width),
            y: fitted.minY + pixel.y * fitted.height / CGFloat(cg.height)
        )
    }

    private func toViewRect(_ pixel: CGRect, fitted: CGRect) -> CGRect? {
        guard let cg = image.youshotCGImage, cg.width > 0, cg.height > 0 else { return nil }
        let scaleX = fitted.width / CGFloat(cg.width)
        let scaleY = fitted.height / CGFloat(cg.height)
        return CGRect(
            x: fitted.minX + pixel.minX * scaleX,
            y: fitted.minY + pixel.minY * scaleY,
            width: pixel.width * scaleX,
            height: pixel.height * scaleY
        )
    }
}

private struct InlineTextField: View {
    private static let placeholder = "输入文字"

    let origin: CGPoint
    let available: CGFloat

    @EnvironmentObject private var controller: CaptureController
    @FocusState private var focused: Bool

    private var font: Font {
        .system(size: controller.annotationFontSize, weight: .bold)
    }

    /// 输入框宽度跟随内容增长，不再一路顶到画布边缘
    private var width: CGFloat {
        let size = controller.annotationFontSize
        let text = controller.textDraft.isEmpty ? Self.placeholder : controller.textDraft
        let measured = (text as NSString).size(
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: size)]
        ).width
        return min(available, measured + size)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if controller.textDraft.isEmpty {
                Text(Self.placeholder)
                    .font(font)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            TextField("", text: $controller.textDraft)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(Color(nsColor: controller.annotationColor))
                .focused($focused)
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 3)
        .background(Color.black.opacity(0.3))
        .overlay {
            Rectangle()
                .strokeBorder(Color(nsColor: controller.annotationColor).opacity(0.8), lineWidth: 1)
        }
        .offset(x: origin.x, y: origin.y - 2)
        .onSubmit { controller.confirmTextInput() }
        .onExitCommand { controller.cancelTextInput() }
        .onAppear { focused = true }
    }
}

@MainActor
private final class DragState: ObservableObject {
    @Published var start: CGPoint?
    @Published var current: CGPoint?
    @Published var points: [CGPoint] = []

    func reset() {
        start = nil
        current = nil
        points = []
    }
}
