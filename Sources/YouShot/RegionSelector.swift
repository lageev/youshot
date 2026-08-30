import AppKit
import QuartzCore

struct RegionSelection: Sendable {
    let displayID: CGDirectDisplayID
    /// Display-local rect in points, top-left origin (ScreenCaptureKit sourceRect).
    let displayLocalRect: CGRect
    /// 吸附到具体窗口时带上窗口号，用于按窗口采集（透明圆角）。
    let windowID: CGWindowID?
}

struct SnapWindowInfo {
    let id: CGWindowID
    let frame: CGRect // Cocoa 全局坐标
    let title: String
}

@MainActor
final class RegionSelector {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private var cursorHiddenDisplays: [CGDirectDisplayID] = []

    func pick(snapWindows: Bool) async -> RegionSelection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(snapWindows: snapWindows)
        }
    }

    func cancel() {
        finish(nil)
    }

    /// 有效选区会保留到截图/标注层接管后才关闭，以避免画面短暂露出原桌面。
    func dismiss() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        cursorHiddenDisplays.forEach { CGDisplayShowCursor($0) }
        cursorHiddenDisplays.removeAll()
    }

    private func present(snapWindows: Bool) {
        let snapList = snapWindows ? Self.collectSnapWindows() : []

        for screen in NSScreen.screens {
            let overlay = RegionOverlayView(frame: screen.frame)
            let displayID = UInt32(
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            )
            overlay.snapWindows = snapList
            overlay.snapEnabled = snapWindows
            overlay.onSelection = { [weak self] globalRect, windowID in
                guard let self else { return }
                if let globalRect {
                    let local = Self.displayLocalRect(globalRect, on: screen)
                    if local.width >= 2, local.height >= 2 {
                        self.finish(
                            RegionSelection(
                                displayID: displayID,
                                displayLocalRect: local,
                                windowID: windowID
                            )
                        )
                        return
                    }
                }
                self.finish(nil)
            }

            let panel = RegionSelectionPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.setFrame(screen.frame, display: true)
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.worksWhenModal = true
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.sharingType = .none
            panel.contentView = overlay
            panel.acceptsMouseMovedEvents = true
            panel.orderFrontRegardless()
            panel.invalidateCursorRects(for: overlay)
            overlay.updateSelectionCursor(globalPoint: NSEvent.mouseLocation)
            panels.append(panel)
        }
        if let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
           let overlay = panel.contentView
        {
            panel.invalidateCursorRects(for: overlay)
        }
        for screen in NSScreen.screens {
            let id = UInt32(
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            )
            if CGDisplayHideCursor(id) == .success {
                cursorHiddenDisplays.append(id)
            }
        }
        // 保持目标应用为前台：部分应用的设置面板会在失焦后自动关闭。
        // 非激活面板仍可接收鼠标事件；取消操作由全局 Esc 热键处理。
    }

    private func finish(_ selection: RegionSelection?) {
        if selection == nil {
            dismiss()
        }
        let cont = continuation
        continuation = nil
        cont?.resume(returning: selection)
    }

    /// Convert global Cocoa rect (bottom-left origin) to display-local top-left points.
    private static func displayLocalRect(_ global: CGRect, on screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let x = global.minX - frame.minX
        let y = frame.maxY - global.maxY
        return CGRect(x: x, y: y, width: global.width, height: global.height)
            .integral
    }

    private static func collectSnapWindows() -> [SnapWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [SnapWindowInfo] = []
        for info in infoList {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.05 else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "Window Server" { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            let x = (bounds["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
            let w = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let h = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            guard w >= 40, h >= 40 else { continue }

            let quartz = CGRect(x: x, y: y, width: w, height: h)
            let cocoa = cocoaFrame(fromQuartz: quartz)
            let title = info[kCGWindowName as String] as? String
            let label = (title?.isEmpty == false) ? (title ?? owner) : owner
            result.append(SnapWindowInfo(id: number, frame: cocoa, title: label))
        }
        return result
    }

    /// Quartz 窗口 bounds（主屏左上为原点、Y 向下）→ Cocoa 全局坐标。
    private static func cocoaFrame(fromQuartz quartz: CGRect) -> CGRect {
        let mainID = CGMainDisplayID()
        let mainScreen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainID
        } ?? NSScreen.main ?? NSScreen.screens[0]

        return CGRect(
            x: mainScreen.frame.minX + quartz.origin.x,
            y: mainScreen.frame.maxY - quartz.origin.y - quartz.height,
            width: quartz.width,
            height: quartz.height
        )
    }
}

private final class RegionOverlayView: NSView {
    var onSelection: ((CGRect?, CGWindowID?) -> Void)?
    var snapWindows: [SnapWindowInfo] = []
    var snapEnabled = false

    private var startPoint: CGPoint?
    private var currentRect: CGRect?
    private var hoverWindow: SnapWindowInfo?
    private var isDragging = false
    private var preservesVisualsAfterSelection = false
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let snapLayer = CAShapeLayer()
    private let cursorOutlineLayer = CAShapeLayer()
    private let cursorLayer = CAShapeLayer()
    private let sizeLabel = NSTextField(labelWithString: "")

    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
        dimLayer.path = CGPath(rect: bounds, transform: nil)
        layer?.addSublayer(dimLayer)

        // 窗口吸附只保留透亮选区与描边，不在窗口内容上叠加颜色。
        snapLayer.fillColor = NSColor.clear.cgColor
        snapLayer.strokeColor = NSColor.white.cgColor
        snapLayer.lineWidth = 1.5
        snapLayer.lineDashPattern = [6, 4]
        snapLayer.isHidden = true
        layer?.addSublayer(snapLayer)

        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.lineDashPattern = [6, 4]
        layer?.addSublayer(borderLayer)

        sizeLabel.textColor = .white
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.drawsBackground = true
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        sizeLabel.isBezeled = false
        sizeLabel.isHidden = true
        addSubview(sizeLabel)

        let cursorPath = CGMutablePath()
        cursorPath.move(to: CGPoint(x: -11, y: 0))
        cursorPath.addLine(to: CGPoint(x: -3, y: 0))
        cursorPath.move(to: CGPoint(x: 3, y: 0))
        cursorPath.addLine(to: CGPoint(x: 11, y: 0))
        cursorPath.move(to: CGPoint(x: 0, y: -11))
        cursorPath.addLine(to: CGPoint(x: 0, y: -3))
        cursorPath.move(to: CGPoint(x: 0, y: 3))
        cursorPath.addLine(to: CGPoint(x: 0, y: 11))

        cursorOutlineLayer.path = cursorPath
        cursorOutlineLayer.fillColor = NSColor.clear.cgColor
        cursorOutlineLayer.strokeColor = NSColor.black.withAlphaComponent(0.85).cgColor
        cursorOutlineLayer.lineWidth = 3
        cursorOutlineLayer.lineCap = .round
        cursorOutlineLayer.zPosition = 100
        layer?.addSublayer(cursorOutlineLayer)

        cursorLayer.path = cursorPath
        cursorLayer.fillColor = NSColor.clear.cgColor
        cursorLayer.strokeColor = NSColor.white.cgColor
        cursorLayer.lineWidth = 1
        cursorLayer.lineCap = .round
        cursorLayer.zPosition = 101
        layer?.addSublayer(cursorLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        updateSelectionCursor(globalPoint: NSEvent.mouseLocation)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseMoved(with event: NSEvent) {
        updateSelectionCursor(localPoint: convert(event.locationInWindow, from: nil))
        guard snapEnabled, !isDragging, startPoint == nil else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        updateSelectionCursor(localPoint: convert(event.locationInWindow, from: nil))
        // Option 临时关闭吸附
        let ignoreSnap = event.modifierFlags.contains(.option)
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        isDragging = false
        if ignoreSnap {
            hoverWindow = nil
        } else if snapEnabled {
            updateHover(at: startPoint!)
        }
        updateVisuals()
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelectionCursor(localPoint: convert(event.locationInWindow, from: nil))
        guard let startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - startPoint.x, point.y - startPoint.y)
        if distance >= 4 {
            isDragging = true
            hoverWindow = nil
            currentRect = CGRect(
                x: min(startPoint.x, point.x),
                y: min(startPoint.y, point.y),
                width: abs(point.x - startPoint.x),
                height: abs(point.y - startPoint.y)
            )
        }
        updateVisuals()
    }

    override func mouseUp(with event: NSEvent) {
        updateSelectionCursor(localPoint: convert(event.locationInWindow, from: nil))
        defer {
            if !preservesVisualsAfterSelection {
                startPoint = nil
                currentRect = nil
                isDragging = false
                updateVisuals()
            }
        }

        // 单击吸附窗口
        if snapEnabled, !isDragging, let hover = hoverWindow {
            preservesVisualsAfterSelection = true
            onSelection?(hover.frame, hover.id)
            return
        }

        guard let currentRect, currentRect.width >= 2, currentRect.height >= 2 else {
            // 无有效拖拽且无吸附：取消
            if hoverWindow == nil {
                onSelection?(nil, nil)
            }
            return
        }
        let global = window?.convertToScreen(currentRect) ?? currentRect
        preservesVisualsAfterSelection = true
        onSelection?(global, nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onSelection?(nil, nil)
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onSelection?(nil, nil)
    }

    private func updateHover(at localPoint: CGPoint) {
        guard let window else {
            hoverWindow = nil
            updateVisuals()
            return
        }
        let globalPoint = window.convertToScreen(NSRect(origin: localPoint, size: .zero)).origin
        // 列表前到后为前台到后台，取第一个包含点的窗口
        hoverWindow = snapWindows.first { $0.frame.contains(globalPoint) }
        updateVisuals()
    }

    func updateSelectionCursor(globalPoint: CGPoint) {
        guard let window else { return }
        let windowPoint = window.convertFromScreen(NSRect(origin: globalPoint, size: .zero)).origin
        updateSelectionCursor(localPoint: convert(windowPoint, from: nil))
    }

    private func updateSelectionCursor(localPoint: CGPoint) {
        let visible = bounds.contains(localPoint)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorOutlineLayer.position = localPoint
        cursorLayer.position = localPoint
        cursorOutlineLayer.isHidden = !visible
        cursorLayer.isHidden = !visible
        CATransaction.commit()
    }

    private func updateVisuals() {
        let boundsPath = CGPath(rect: bounds, transform: nil)
        let path = CGMutablePath()
        path.addPath(boundsPath)

        if let currentRect, isDragging {
            path.addPath(CGPath(rect: currentRect, transform: nil))
            borderLayer.path = CGPath(rect: currentRect, transform: nil)
            borderLayer.isHidden = false
            snapLayer.isHidden = true
            sizeLabel.stringValue = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
            sizeLabel.sizeToFit()
            let labelSize = sizeLabel.frame.size
            sizeLabel.frame.origin = CGPoint(
                x: currentRect.midX - labelSize.width / 2,
                y: min(currentRect.maxY + 8, bounds.maxY - labelSize.height - 4)
            )
            sizeLabel.isHidden = false
            dimLayer.path = path
            dimLayer.isHidden = false
        } else if let hover = hoverWindow, let window, snapEnabled {
            let local = convertFromScreen(hover.frame, window: window)
            path.addPath(CGPath(rect: local, transform: nil))
            snapLayer.path = CGPath(rect: local, transform: nil)
            snapLayer.isHidden = false
            borderLayer.isHidden = true
            let name = hover.title.isEmpty ? "窗口" : hover.title
            sizeLabel.stringValue = "\(name)  ·  单击选取"
            sizeLabel.sizeToFit()
            let labelSize = sizeLabel.frame.size
            sizeLabel.frame.origin = CGPoint(
                x: local.midX - labelSize.width / 2,
                y: min(local.maxY + 8, bounds.maxY - labelSize.height - 4)
            )
            sizeLabel.isHidden = false
            dimLayer.path = path
            dimLayer.isHidden = false
        } else {
            borderLayer.isHidden = true
            snapLayer.isHidden = true
            sizeLabel.isHidden = true
            dimLayer.path = boundsPath
            dimLayer.isHidden = false
        }
        needsDisplay = true
    }
}

private final class RegionSelectionPanel: NSPanel {
    /// 保留非激活面板接收鼠标事件的资格；是否实际成为 key 由
    /// `becomesKeyOnlyIfNeeded` + `needsPanelToBecomeKey` 控制。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension RegionOverlayView {
    func convertFromScreen(_ rect: CGRect, window: NSWindow) -> CGRect {
        window.convertFromScreen(rect)
    }
}
