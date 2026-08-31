import AppKit
import SwiftUI

/// 全屏覆盖层：用整屏截图当背景，选区在原位标注。不是普通应用窗口。
@MainActor
final class AnnotationOverlay {
    static let shared = AnnotationOverlay()

    private var panel: OverlayPanel?
    private weak var controller: CaptureController?

    func present(
        controller: CaptureController,
        screenFrame: CGRect,
        selectionFrame: CGRect,
        backdrop: NSImage
    ) {
        dismiss()
        hideTitledWindows()
        self.controller = controller

        let root = AnnotationOverlayRoot(
            screenSize: screenFrame.size,
            selectionInScreen: CGRect(
                x: selectionFrame.minX - screenFrame.minX,
                y: screenFrame.maxY - selectionFrame.maxY,
                width: selectionFrame.width,
                height: selectionFrame.height
            ),
            backdrop: backdrop
        )
        .environmentObject(controller)

        let hosting = NSHostingView(rootView: root)
        hosting.safeAreaRegions = []
        hosting.wantsLayer = true

        // 用固定尺寸容器承载 SwiftUI，避免 NSHostingView 把面板收成选区大小的小窗口
        let container = NSView(frame: NSRect(origin: .zero, size: screenFrame.size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        let created = OverlayPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = false
        created.level = .screenSaver
        created.backgroundColor = .black
        created.isOpaque = true
        created.hasShadow = false
        created.isMovable = false
        created.animationBehavior = .none
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        created.sharingType = .none
        created.acceptsMouseMovedEvents = true
        created.hidesOnDeactivate = false
        created.contentView = container
        created.captureController = controller
        created.setFrame(screenFrame, display: true)
        created.orderFrontRegardless()
        // 成为 key window，标注层内才能直接键入文字、响应 Esc
        created.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        panel = created
        updateInitialCursor(controller: controller, screenFrame: screenFrame)
    }

    var isPresented: Bool { panel != nil }

    func dismiss() {
        CustomColorPanel.shared.close()
        panel?.captureController = nil
        panel?.orderOut(nil)
        panel = nil
        controller = nil
        NSCursor.arrow.set()
    }

    private func hideTitledWindows() {
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.orderOut(nil)
        }
    }

    private func updateInitialCursor(controller: CaptureController, screenFrame: CGRect) {
        let global = NSEvent.mouseLocation
        let point = CGPoint(
            x: global.x - screenFrame.minX,
            y: screenFrame.maxY - global.y
        )
        let selection = controller.overlaySelection
        guard selection.contains(point) else {
            NSCursor.arrow.set()
            return
        }
        let local = CGPoint(x: point.x - selection.minX, y: point.y - selection.minY)
        if let cursor = OverlayCursor.resizeCursor(at: local, in: selection.size) {
            cursor.set()
            return
        }
        switch controller.editorTool {
        case .text:
            NSCursor.iBeam.set()
        case .pen:
            let width = CGFloat(controller.strokeWidth) * controller.penBrush.widthScale
            let color = controller.annotationColor.withAlphaComponent(controller.strokeOpacity)
            OverlayCursor.pen(color: color, diameter: width).set()
        case .watermark:
            NSCursor.arrow.set()
        case .rect, .line, .arrow, .highlight, .mosaic, .blur:
            NSCursor.crosshair.set()
        }
    }
}

private final class OverlayPanel: NSPanel {
    weak var captureController: CaptureController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        guard let captureController else { return }
        if captureController.showTextInput {
            captureController.cancelTextInput()
        } else {
            captureController.cancelEditor()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelOperation(nil)
            return
        }
        super.keyDown(with: event)
    }
}

struct AnnotationOverlayRoot: View {
    let screenSize: CGSize
    let selectionInScreen: CGRect
    let backdrop: NSImage
    @EnvironmentObject private var controller: CaptureController

    private var liveSelection: CGRect {
        controller.overlaySelection == .zero ? selectionInScreen : controller.overlaySelection
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: backdrop)
                .resizable()
                .interpolation(.high)
                .frame(width: screenSize.width, height: screenSize.height)
                .allowsHitTesting(false)

            // 与区域选择层保持一致，避免截图完成交接标注层时非选区瞬间变暗。
            Color.black.opacity(0.35)
                .frame(width: screenSize.width, height: screenSize.height)
                .mask {
                    Rectangle()
                        .fill(.white)
                        .overlay(alignment: .topLeading) {
                            Rectangle()
                                .frame(width: liveSelection.width, height: liveSelection.height)
                                .offset(x: liveSelection.minX, y: liveSelection.minY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }
                .allowsHitTesting(false)

            sizeLabel
                .position(
                    x: liveSelection.midX,
                    y: max(16, liveSelection.minY - 18)
                )
                .allowsHitTesting(false)
                .zIndex(2)

            if !controller.overlayResizing, let image = controller.editorImage {
                AnnotationCanvas(image: image, canvasSize: liveSelection.size)
                .frame(width: liveSelection.width, height: liveSelection.height)
                .offset(x: liveSelection.minX, y: liveSelection.minY)
                .zIndex(1)
            }

            SelectionResizeChrome(screenSize: screenSize)
                .zIndex(4)

            FloatingAnnotateToolbar()
                .position(x: toolbarCenterX, y: toolbarCenterY)
                .zIndex(5)

            if let toast = controller.overlayToast {
                Text(toast)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.78), in: Capsule())
                    .position(x: toolbarCenterX, y: max(24, toolbarCenterY - 96))
                    .allowsHitTesting(false)
                    .zIndex(6)
            }
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .clipped()
        .ignoresSafeArea()
        .coordinateSpace(name: "overlay")
        .onExitCommand {
            if controller.showTextInput {
                controller.cancelTextInput()
            } else {
                controller.cancelEditor()
            }
        }
    }

    private var sizeLabel: some View {
        let scale = controller.editorPixelScale
        let width = max(1, Int((liveSelection.width * scale.width).rounded()))
        let height = max(1, Int((liveSelection.height * scale.height).rounded()))
        return Text("\(width) × \(height)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 2)
    }

    private var toolbarCenterX: CGFloat {
        min(max(liveSelection.midX, 360), screenSize.width - 360)
    }

    private var toolbarCenterY: CGFloat {
        let below = liveSelection.maxY + 72
        if below + 80 < screenSize.height - 12 {
            return below
        }
        let above = liveSelection.minY - 72
        if above > 80 {
            return above
        }
        return screenSize.height - 88
    }
}

/// Central cursor palette for the capture/editor overlay. AppKit's standard
/// cursors are used whenever they express the action accurately; diagonal
/// resize cursors are drawn as resolution-independent NSImages on macOS 14,
/// where AppKit does not expose the native frame-resize variants publicly.
@MainActor
enum OverlayCursor {
    enum ResizeDirection {
        case horizontal
        case vertical
        case northwestSoutheast
        case northeastSouthwest
    }

    private static var penCache: [String: NSCursor] = [:]
    private static let northwestSoutheast = diagonalResizeCursor(descending: true)
    private static let northeastSouthwest = diagonalResizeCursor(descending: false)

    static func resize(_ direction: ResizeDirection) -> NSCursor {
        if #available(macOS 15.0, *) {
            switch direction {
            case .horizontal:
                return .frameResize(position: .left, directions: .all)
            case .vertical:
                return .frameResize(position: .top, directions: .all)
            case .northwestSoutheast:
                return .frameResize(position: .topLeft, directions: .all)
            case .northeastSouthwest:
                return .frameResize(position: .topRight, directions: .all)
            }
        }

        switch direction {
        case .horizontal: return .resizeLeftRight
        case .vertical: return .resizeUpDown
        case .northwestSoutheast: return northwestSoutheast
        case .northeastSouthwest: return northeastSouthwest
        }
    }

    static func pen(color: NSColor, diameter: CGFloat) -> NSCursor {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let dotDiameter = min(max(diameter, 3), 28)
        let key = String(
            format: "%.2f-%.2f-%.2f-%.2f-%.1f",
            rgb.redComponent,
            rgb.greenComponent,
            rgb.blueComponent,
            rgb.alphaComponent,
            dotDiameter
        )
        if let cached = penCache[key] { return cached }

        let size = max(18, dotDiameter + 8)
        let center = NSPoint(x: size / 2, y: size / 2)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let rect = NSRect(
                x: center.x - dotDiameter / 2,
                y: center.y - dotDiameter / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            let dot = NSBezierPath(ovalIn: rect)
            rgb.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.72).setStroke()
            dot.lineWidth = 3
            dot.stroke()
            NSColor.white.withAlphaComponent(0.95).setStroke()
            dot.lineWidth = 1
            dot.stroke()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: center)
        penCache[key] = cursor
        return cursor
    }

    static func resizeCursor(
        at point: CGPoint,
        in size: CGSize,
        hitRadius: CGFloat = 12
    ) -> NSCursor? {
        let targets: [(CGPoint, ResizeDirection)] = [
            (CGPoint(x: 0, y: 0), .northwestSoutheast),
            (CGPoint(x: size.width / 2, y: 0), .vertical),
            (CGPoint(x: size.width, y: 0), .northeastSouthwest),
            (CGPoint(x: 0, y: size.height / 2), .horizontal),
            (CGPoint(x: size.width, y: size.height / 2), .horizontal),
            (CGPoint(x: 0, y: size.height), .northeastSouthwest),
            (CGPoint(x: size.width / 2, y: size.height), .vertical),
            (CGPoint(x: size.width, y: size.height), .northwestSoutheast),
        ]
        guard let target = targets.first(where: {
            abs($0.0.x - point.x) <= hitRadius && abs($0.0.y - point.y) <= hitRadius
        }) else { return nil }
        return resize(target.1)
    }

    private static func diagonalResizeCursor(descending: Bool) -> NSCursor {
        let size: CGFloat = 24
        let start = descending ? NSPoint(x: 4, y: 20) : NSPoint(x: 4, y: 4)
        let end = descending ? NSPoint(x: 20, y: 4) : NSPoint(x: 20, y: 20)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let path = diagonalArrowPath(from: start, to: end)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.withAlphaComponent(0.72).setStroke()
            path.lineWidth = 5
            path.stroke()
            NSColor.white.setStroke()
            path.lineWidth = 2
            path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }

    private static func diagonalArrowPath(from start: NSPoint, to end: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux
        let arrowLength: CGFloat = 5.5
        let arrowWidth: CGFloat = 3.4

        for (tip, inward) in [(end, CGFloat(-1)), (start, CGFloat(1))] {
            let base = NSPoint(
                x: tip.x + ux * arrowLength * inward,
                y: tip.y + uy * arrowLength * inward
            )
            path.move(to: tip)
            path.line(to: NSPoint(x: base.x + px * arrowWidth, y: base.y + py * arrowWidth))
            path.move(to: tip)
            path.line(to: NSPoint(x: base.x - px * arrowWidth, y: base.y - py * arrowWidth))
        }
        return path
    }
}

@MainActor
private enum SelectionGrip: String, CaseIterable {
    case nw, n, ne, w, e, sw, s, se

    var cursor: NSCursor {
        switch self {
        case .w, .e:
            return OverlayCursor.resize(.horizontal)
        case .n, .s:
            return OverlayCursor.resize(.vertical)
        case .nw, .se:
            return OverlayCursor.resize(.northwestSoutheast)
        case .ne, .sw:
            return OverlayCursor.resize(.northeastSouthwest)
        }
    }
}

/// 选区边框与八个调整手柄。
private struct SelectionResizeChrome: View {
    let screenSize: CGSize
    @EnvironmentObject private var controller: CaptureController

    private var rect: CGRect { controller.overlaySelection }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)

            ForEach(SelectionGrip.allCases, id: \.self) { grip in
                let point = position(for: grip)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                    .padding(7)
                    .contentShape(Rectangle())
                    .position(point)
                    .gesture(drag(grip))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            grip.cursor.set()
                        case .ended:
                            NSCursor.arrow.set()
                        }
                    }
            }
        }
        .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
        .contentShape(HandleHitShape(rect: rect))
    }

    private func position(for grip: SelectionGrip) -> CGPoint {
        switch grip {
        case .nw: return CGPoint(x: rect.minX, y: rect.minY)
        case .n: return CGPoint(x: rect.midX, y: rect.minY)
        case .ne: return CGPoint(x: rect.maxX, y: rect.minY)
        case .w: return CGPoint(x: rect.minX, y: rect.midY)
        case .e: return CGPoint(x: rect.maxX, y: rect.midY)
        case .sw: return CGPoint(x: rect.minX, y: rect.maxY)
        case .s: return CGPoint(x: rect.midX, y: rect.maxY)
        case .se: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func drag(_ grip: SelectionGrip) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("overlay"))
            .onChanged { value in
                grip.cursor.set()
                if controller.overlayResizeOrigin == nil {
                    controller.overlayResizeOrigin = rect
                    controller.overlayResizing = true
                }
                guard let start = controller.overlayResizeOrigin else { return }
                controller.overlaySelection = Self.resized(
                    from: start,
                    grip: grip,
                    to: value.location,
                    limits: screenSize
                )
            }
            .onEnded { value in
                grip.cursor.set()
                let origin = controller.overlayResizeOrigin ?? rect
                controller.overlayResizeOrigin = nil
                controller.overlayResizing = false
                let next = Self.resized(from: origin, grip: grip, to: value.location, limits: screenSize)
                controller.overlaySelection = next
                controller.recropSelection(inScreen: next)
            }
    }

    private static func resized(
        from start: CGRect,
        grip: SelectionGrip,
        to point: CGPoint,
        limits: CGSize
    ) -> CGRect {
        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY
        switch grip {
        case .n, .nw, .ne: minY = point.y
        case .s, .sw, .se: maxY = point.y
        case .w, .e: break
        }
        switch grip {
        case .w, .nw, .sw: minX = point.x
        case .e, .ne, .se: maxX = point.x
        case .n, .s: break
        }
        if maxX < minX { swap(&maxX, &minX) }
        if maxY < minY { swap(&maxY, &minY) }

        var result = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if result.width < 16 {
            result.size.width = 16
        }
        if result.height < 16 {
            result.size.height = 16
        }
        result.origin.x = min(max(0, result.origin.x), max(0, limits.width - result.width))
        result.origin.y = min(max(0, result.origin.y), max(0, limits.height - result.height))
        result.size.width = min(result.width, limits.width - result.origin.x)
        result.size.height = min(result.height, limits.height - result.origin.y)
        return result
    }
}

/// 只让八个手柄接收点击，避免挡住选区内标注。
private struct HandleHitShape: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path()
        let size: CGFloat = 24
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        for point in points {
            path.addRect(CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
        }
        return path
    }
}
