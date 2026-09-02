import AppKit
import QuartzCore

enum RegionCaptureAction: Sendable {
    case standard
    case scrollManual
    case scrollAutomatic
}

struct RegionSelection: Sendable {
    let displayID: CGDirectDisplayID
    /// Display-local rect in points, top-left origin (ScreenCaptureKit sourceRect).
    let displayLocalRect: CGRect
    /// 吸附到具体窗口时带上窗口号，用于按窗口采集（透明圆角）。
    let windowID: CGWindowID?
    let action: RegionCaptureAction

    init(
        displayID: CGDirectDisplayID,
        displayLocalRect: CGRect,
        windowID: CGWindowID?,
        action: RegionCaptureAction = .standard
    ) {
        self.displayID = displayID
        self.displayLocalRect = displayLocalRect
        self.windowID = windowID
        self.action = action
    }

    func withAction(_ action: RegionCaptureAction) -> RegionSelection {
        RegionSelection(
            displayID: displayID,
            displayLocalRect: displayLocalRect,
            windowID: windowID,
            action: action
        )
    }
}

struct SnapWindowInfo {
    let id: CGWindowID
    /// 高层级菜单/浮层依赖屏幕合成后的背景，不能再按独立窗口采集。
    let captureWindowID: CGWindowID?
    let frame: CGRect // Cocoa 全局坐标
    let title: String
}

@MainActor
final class RegionSelector {
    private var panels: [NSPanel] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private var actionPanel: RegionActionPanel?
    private var allowsScrollCapture = false

    func pick(
        snapWindows: Bool,
        frozenFrames: [CGDirectDisplayID: CGImage] = [:],
        allowsScrollCapture: Bool = false
    ) async -> RegionSelection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.allowsScrollCapture = allowsScrollCapture
            present(snapWindows: snapWindows, frozenFrames: frozenFrames)
        }
    }

    func cancel() {
        finish(nil)
    }

    /// 有效选区会保留到截图/标注层接管后才关闭，以避免画面短暂露出原桌面。
    func dismiss(restoreCursor: Bool = true) {
        actionPanel?.orderOut(nil)
        actionPanel = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        // Selection views install a full-view crosshair cursor rect. Restore a
        // normal pointer immediately instead of waiting for the next AppKit
        // mouse event after the panels disappear.
        if restoreCursor {
            NSCursor.arrow.set()
        }
    }

    private func present(
        snapWindows: Bool,
        frozenFrames: [CGDirectDisplayID: CGImage]
    ) {
        let snapList = snapWindows ? Self.collectSnapWindows() : []

        for screen in NSScreen.screens {
            let displayID = UInt32(
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            )
            let overlay = RegionOverlayView(
                frame: screen.frame,
                frozenFrame: frozenFrames[displayID]
            )
            overlay.snapWindows = snapList
            overlay.snapEnabled = snapWindows
            overlay.onSelection = { [weak self] globalRect, windowID in
                guard let self else { return }
                if let globalRect {
                    let local = Self.displayLocalRect(globalRect, on: screen)
                    if local.width >= 2, local.height >= 2 {
                        let selection = RegionSelection(
                            displayID: displayID,
                            displayLocalRect: local,
                            windowID: windowID
                        )
                        if self.allowsScrollCapture {
                            self.presentActions(for: selection, beside: globalRect, on: screen)
                        } else {
                            self.finish(selection)
                        }
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
            // 冻结帧覆盖整屏后，NSPanel 默认的入场/Space 联动动画会让
            // 画面看起来整体漂移。选区层必须在原位置无动画瞬时出现。
            panel.animationBehavior = .none
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]
            panel.sharingType = .none
            panel.contentView = overlay
            panel.acceptsMouseMovedEvents = true
            panel.orderFrontRegardless()
            panel.invalidateCursorRects(for: overlay)
            panels.append(panel)
        }
        // A non-activating panel can become key without taking focus from the
        // app being captured. Making the panel under the pointer key gives
        // WindowServer ownership of its cursor rect, while mouse-event updates
        // below provide a fallback on the other displays.
        if let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
           let overlay = panel.contentView {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(overlay)
            panel.invalidateCursorRects(for: overlay)
            NSCursor.crosshair.set()
        }
        // 保持目标应用为前台：部分应用的设置面板会在失焦后自动关闭。
        // key 的非激活面板仍可接收鼠标事件；取消操作由全局 Esc 热键处理。
    }

    private func finish(_ selection: RegionSelection?) {
        actionPanel?.orderOut(nil)
        actionPanel = nil
        if selection == nil {
            dismiss()
        }
        let cont = continuation
        continuation = nil
        cont?.resume(returning: selection)
    }

    private func presentActions(
        for selection: RegionSelection,
        beside globalRect: CGRect,
        on screen: NSScreen
    ) {
        actionPanel?.orderOut(nil)
        panels.forEach { ($0.contentView as? RegionOverlayView)?.selectionLocked = true }
        let panel = RegionActionPanel()
        panel.onAction = { [weak self] action in
            guard let self else { return }
            self.finish(selection.withAction(action))
        }
        panel.onCancel = { [weak self] in self?.finish(nil) }
        panel.position(relativeTo: globalRect, on: screen)
        panel.orderFrontRegardless()
        actionPanel = panel
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

        let selectableLayers = Set([
            CGWindowLevelForKey(.normalWindow),
            CGWindowLevelForKey(.floatingWindow),
            CGWindowLevelForKey(.modalPanelWindow),
            CGWindowLevelForKey(.utilityWindow),
            CGWindowLevelForKey(.popUpMenuWindow),
        ].map(Int.init))
        let primaryScreenArea = NSScreen.screens.first.map {
            $0.frame.width * $0.frame.height
        } ?? 0

        var result: [SnapWindowInfo] = []
        for info in infoList {
            guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  selectableLayers.contains(layer)
            else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.05 else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "Window Server" { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            let x = (bounds["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
            let w = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let h = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            guard w >= 8, h >= 8 else { continue }
            // 输入法背景等 WindowServer 高层透明面可能覆盖近乎整屏，若参与
            // 命中测试会挡住其下方真正需要选择的窗口。
            if layer >= 20, primaryScreenArea > 0, w * h > primaryScreenArea * 0.8 {
                continue
            }

            let quartz = CGRect(x: x, y: y, width: w, height: h)
            let cocoa = cocoaFrame(fromQuartz: quartz)
            let title = info[kCGWindowName as String] as? String
            let label = (title?.isEmpty == false) ? (title ?? owner) : owner
            // Popup-menu 等高层窗口通常带有透明/模糊背景，并且会在失焦时
            // 立即销毁。它们必须从触发瞬间的整屏合成帧裁剪。
            let captureWindowID = layer >= 20 ? nil : number
            result.append(
                SnapWindowInfo(
                    id: number,
                    captureWindowID: captureWindowID,
                    frame: cocoa,
                    title: label
                )
            )
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
    var selectionLocked = false

    private var startPoint: CGPoint?
    private var currentRect: CGRect?
    private var hoverWindow: SnapWindowInfo?
    private var isDragging = false
    private var preservesVisualsAfterSelection = false
    private let frozenFrame: NSImage?
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let snapLayer = CAShapeLayer()
    private let sizeLabel = NSTextField(labelWithString: "")

    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame frameRect: NSRect, frozenFrame: CGImage?) {
        self.frozenFrame = frozenFrame.map { NSImage(cgImage: $0, size: frameRect.size) }
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        frozenFrame?.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard snapEnabled, !isDragging, startPoint == nil else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard !selectionLocked else { return }
        NSCursor.crosshair.set()
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
        guard !selectionLocked else { return }
        NSCursor.crosshair.set()
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
        guard !selectionLocked else { return }
        NSCursor.crosshair.set()
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
            onSelection?(hover.frame, hover.captureWindowID)
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

/// 选区确认条：普通截图直接确认；长截图下拉选择手动或自动滚动。
private final class RegionActionPanel: NSPanel {
    var onAction: ((RegionCaptureAction) -> Void)?
    var onCancel: (() -> Void)?

    private let standardButton = NSButton(title: "截图", target: nil, action: nil)
    private let scrollButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 238, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let effect = NSVisualEffectView(frame: contentView?.bounds ?? .zero)
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 11
        effect.layer?.masksToBounds = true
        contentView = effect

        standardButton.target = self
        standardButton.action = #selector(chooseStandard)
        standardButton.bezelColor = .systemGreen
        scrollButton.addItems(withTitles: ["长截图", "手动滚动", "自动滚动"])
        scrollButton.selectItem(at: 0)
        scrollButton.target = self
        scrollButton.action = #selector(chooseScroll)
        cancelButton.target = self
        cancelButton.action = #selector(cancel)

        let stack = NSStackView(views: [standardButton, scrollButton, cancelButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.frame = effect.bounds
        stack.autoresizingMask = [.width, .height]
        effect.addSubview(stack)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func position(relativeTo rect: CGRect, on screen: NSScreen) {
        let size = frame.size
        var x = rect.midX - size.width / 2
        var y = rect.minY - size.height - 9
        if y < screen.visibleFrame.minY + 6 {
            let above = rect.maxY + 9
            y = above + size.height <= screen.visibleFrame.maxY - 6
                ? above
                : max(screen.visibleFrame.minY + 8, rect.minY + 8)
        }
        x = max(screen.visibleFrame.minX + 6, min(x, screen.visibleFrame.maxX - size.width - 6))
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    @objc private func chooseStandard() { onAction?(.standard) }

    @objc private func chooseScroll() {
        switch scrollButton.indexOfSelectedItem {
        case 1: onAction?(.scrollManual)
        case 2: onAction?(.scrollAutomatic)
        default: break
        }
        scrollButton.selectItem(at: 0)
    }

    @objc private func cancel() { onCancel?() }
}

private extension RegionOverlayView {
    func convertFromScreen(_ rect: CGRect, window: NSWindow) -> CGRect {
        window.convertFromScreen(rect)
    }
}
