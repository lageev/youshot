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
    }

    func dismiss() {
        panel?.captureController = nil
        panel?.orderOut(nil)
        panel = nil
        controller = nil
    }

    private func hideTitledWindows() {
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.orderOut(nil)
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

private enum SelectionGrip: String, CaseIterable {
    case nw, n, ne, w, e, sw, s, se
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
