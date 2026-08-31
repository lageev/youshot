import AppKit
import Combine
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit


@MainActor
final class CaptureController: ObservableObject {
    @Published var delaySeconds: Int = 0
    @Published var includeCursor: Bool = true
    @Published var mode: CaptureMode = .currentDisplay
    /// 设置窗口左侧导航当前项（避免 ContentView 依赖 @State 宏）
    @Published var settingsTabRaw: String = "capture"
    @Published var isBusy: Bool = false
    @Published var remainingSeconds: Int = 0
    @Published var lastPreview: NSImage?
    @Published var lastFileURL: URL?
    @Published var statusMessage: String?
    @Published var hasError: Bool = false

    @Published var blurSigma: Double = AppSettings.blurSigma {
        didSet { AppSettings.blurSigma = blurSigma }
    }
    @Published var blurFeather: Double = AppSettings.blurFeather {
        didSet { AppSettings.blurFeather = blurFeather }
    }
    @Published var windowSnapEnabled: Bool = AppSettings.windowSnapEnabled {
        didSet { AppSettings.windowSnapEnabled = windowSnapEnabled }
    }
    @Published var exportCornerRadius: Double = AppSettings.exportCornerRadius {
        didSet { AppSettings.exportCornerRadius = exportCornerRadius }
    }
    @Published var exportShadowBlur: Double = AppSettings.exportShadowBlur {
        didSet { AppSettings.exportShadowBlur = exportShadowBlur }
    }
    @Published var exportShadowOpacity: Double = AppSettings.exportShadowOpacity {
        didSet { AppSettings.exportShadowOpacity = exportShadowOpacity }
    }
    @Published var strokeColorIndex: Int = AppSettings.strokeColorIndex {
        didSet { AppSettings.strokeColorIndex = strokeColorIndex }
    }
    @Published var strokeCustomHex: String = AppSettings.strokeCustomHex {
        didSet { AppSettings.strokeCustomHex = strokeCustomHex }
    }
    @Published var strokeWidth: Double = AppSettings.strokeWidth {
        didSet { AppSettings.strokeWidth = strokeWidth }
    }
    @Published var rectShape: RectShape = AppSettings.rectShape {
        didSet { AppSettings.rectShape = rectShape }
    }
    @Published var textBackdrop: TextBackdrop = AppSettings.textBackdrop {
        didSet { AppSettings.textBackdrop = textBackdrop }
    }
    @Published var textBackdropColorIndex: Int = AppSettings.textBackdropColorIndex {
        didSet { AppSettings.textBackdropColorIndex = textBackdropColorIndex }
    }
    @Published var textBackdropCustomHex: String = AppSettings.textBackdropCustomHex {
        didSet { AppSettings.textBackdropCustomHex = textBackdropCustomHex }
    }
    @Published var penBrush: PenBrush = AppSettings.penBrush {
        didSet { AppSettings.penBrush = penBrush }
    }
    @Published var strokeOpacity: Double = AppSettings.strokeOpacity {
        didSet { AppSettings.strokeOpacity = strokeOpacity }
    }
    @Published var highlightDim: Double = AppSettings.highlightDim {
        didSet { AppSettings.highlightDim = highlightDim }
    }
    @Published var watermarkText: String = AppSettings.watermarkText {
        didSet { AppSettings.watermarkText = watermarkText }
    }
    @Published var watermarkStyle: WatermarkStyle = AppSettings.watermarkStyle {
        didSet { AppSettings.watermarkStyle = watermarkStyle }
    }
    @Published var watermarkColorIndex: Int = AppSettings.watermarkColorIndex {
        didSet { AppSettings.watermarkColorIndex = watermarkColorIndex }
    }
    @Published var watermarkCustomHex: String = AppSettings.watermarkCustomHex {
        didSet { AppSettings.watermarkCustomHex = watermarkCustomHex }
    }
    @Published var watermarkFontSize: Double = AppSettings.watermarkFontSize {
        didSet { AppSettings.watermarkFontSize = watermarkFontSize }
    }
    @Published var watermarkOpacity: Double = AppSettings.watermarkOpacity {
        didSet { AppSettings.watermarkOpacity = watermarkOpacity }
    }

    @Published var hotKeyCurrent: KeyChord = HotKeyDefaults.loadCurrent()
    @Published var hotKeyRegion: KeyChord = HotKeyDefaults.loadRegion()
    @Published var hotKeyAll: KeyChord = HotKeyDefaults.loadAll()

    @Published var editorImage: NSImage?
    @Published var editorURL: URL?
    @Published var editorTool: EditorTool = .rect {
        didSet {
            guard oldValue == .text, editorTool != .text, showTextInput else { return }
            if textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cancelTextInput()
            } else {
                confirmTextInput()
            }
        }
    }
    @Published private(set) var canUndoEditor = false
    @Published private(set) var canRedoEditor = false
    @Published var recordingHotKeyMode: CaptureMode?
    @Published var showTextInput = false
    @Published var textDraft = ""
    @Published var pendingTextPoint: CGPoint?
    @Published var overlaySelection = CGRect.zero
    @Published var overlayResizing = false
    /// 高亮区域（截图像素坐标），共用一层遮罩，导出时才合入图片
    @Published var highlightRects: [CGRect] = []
    /// 圆角矩形 / 椭圆 / 文字：先叠在画布上，可拖动，导出时才合入图片
    @Published var overlays: [OverlayItem] = []
    @Published var overlayToast: String?
    var overlayResizeOrigin: CGRect?

    var onHotKeysChanged: (() -> Void)?
    var onEscapeCancelEnabled: ((Bool) -> Void)?
    private var hotKeyMonitor: Any?
    private var editorBaseImage: NSImage?
    private var editorRedoStack: [EditorSnapshot] = []
    private var toastTask: Task<Void, Never>?
    private var editorBackdrop: NSImage?
    private var editorBackdropCG: CGImage?
    private var editorHostScreenFrame: CGRect?
    private var editorSelectionFrame: CGRect?

    var editorPixelScale: CGSize {
        guard let full = editorBackdropCG, let screen = editorHostScreenFrame, screen.width > 0, screen.height > 0 else {
            return CGSize(width: 2, height: 2)
        }
        return CGSize(
            width: CGFloat(full.width) / screen.width,
            height: CGFloat(full.height) / screen.height
        )
    }

    var annotationColor: NSColor { AnnotationPalette.resolved(index: strokeColorIndex, customHex: strokeCustomHex) }

    var textBackdropColor: NSColor {
        AnnotationPalette.resolved(index: textBackdropColorIndex, customHex: textBackdropCustomHex)
    }

    /// 文字标注字号（点），跟随粗细变化
    var annotationFontSize: Double { strokeWidth * 6 }

    private var strokePixelWidth: CGFloat {
        max(1, CGFloat(strokeWidth) * editorPixelScale.width)
    }

    var countdownText: String {
        if remainingSeconds > 0 {
            return "\(remainingSeconds) 秒后截图"
        }
        return "正在截图…"
    }

    var hasScreenPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var hasEditor: Bool { editorImage != nil }

    private var captureTask: Task<Void, Never>?
    private let hud = CountdownHUD()
    private let regionSelector = RegionSelector()
    private var editorUndoStack: [EditorSnapshot] = []

    func shortcut(for mode: CaptureMode) -> String {
        switch mode {
        case .currentDisplay: return hotKeyCurrent.displayString
        case .region: return hotKeyRegion.displayString
        case .allDisplays: return hotKeyAll.displayString
        }
    }

    func setHotKey(_ chord: KeyChord, for mode: CaptureMode) {
        switch mode {
        case .currentDisplay:
            hotKeyCurrent = chord
            HotKeyDefaults.saveCurrent(chord)
        case .region:
            hotKeyRegion = chord
            HotKeyDefaults.saveRegion(chord)
        case .allDisplays:
            hotKeyAll = chord
            HotKeyDefaults.saveAll(chord)
        }
        onHotKeysChanged?()
        statusMessage = "已更新快捷键：\(mode.title) \(chord.displayString)"
        hasError = false
    }

    func beginHotKeyRecording(_ mode: CaptureMode) {
        stopHotKeyRecording()
        recordingHotKeyMode = mode
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.stopHotKeyRecording() }
                return nil
            }
            guard let chord = KeyChord.from(event: event) else { return nil }
            Task { @MainActor in
                guard let self, let mode = self.recordingHotKeyMode else { return }
                self.setHotKey(chord, for: mode)
                self.stopHotKeyRecording()
            }
            return nil
        }
    }

    func stopHotKeyRecording() {
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
        }
        hotKeyMonitor = nil
        recordingHotKeyMode = nil
    }

    func requestPermissionIfNeeded() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            hasError = true
            statusMessage = "需要屏幕录制权限才能截图"
        }
    }

    func openScreenRecordingSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func startCapture(mode overrideMode: CaptureMode? = nil) {
        guard !isBusy else { return }
        if let overrideMode {
            mode = overrideMode
        }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            hasError = true
            statusMessage = "未获得屏幕录制权限，请在系统设置中授权后重试"
            return
        }
        captureTask?.cancel()
        hasError = false
        statusMessage = nil
        setBusy(true)
        let captureMode = mode
        captureTask = Task { [weak self] in
            await self?.runCapture(mode: captureMode)
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
        regionSelector.cancel()
        hud.close()
        finishIdle(message: "已取消")
    }

    func revealLastFile() {
        guard let url = lastFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSaveFolder() {
        NSWorkspace.shared.open(saveDirectory)
    }

    // MARK: - Editor

    func applyRect(pixelRect: CGRect) {
        let kind: OverlayItem.OverlayKind = rectShape == .ellipse ? .ellipse : .roundedRect
        pushHistory()
        overlays.append(
            .shape(kind, frame: pixelRect, color: annotationColor, lineWidth: strokePixelWidth)
        )
        refreshEditorPreview()
    }

    func applyLine(from: CGPoint, to: CGPoint) {
        let color = annotationColor
        let width = strokePixelWidth
        commitEdit { AnnotationRenderer.drawLine(on: $0, from: from, to: to, color: color, lineWidth: width) }
    }

    func applyArrow(from: CGPoint, to: CGPoint) {
        let color = annotationColor
        let width = strokePixelWidth
        commitEdit { AnnotationRenderer.drawArrow(on: $0, from: from, to: to, color: color, lineWidth: width) }
    }

    func applyPen(points: [CGPoint]) {
        let color = annotationColor
        let width = strokePixelWidth
        let brush = penBrush
        let opacity = CGFloat(strokeOpacity)
        commitEdit {
            AnnotationRenderer.drawPen(
                on: $0,
                points: points,
                color: color,
                lineWidth: width,
                brush: brush,
                opacity: opacity
            )
        }
    }

    /// 水印按次叠加，应用后切回矩形工具收起水印设置，避免重复添加。
    func applyWatermark() {
        let text = watermarkText
        let style = watermarkStyle
        let scale = editorPixelScale.width
        let fontSize = CGFloat(watermarkFontSize) * scale
        let color = AnnotationPalette.resolved(index: watermarkColorIndex, customHex: watermarkCustomHex)
        let opacity = CGFloat(watermarkOpacity)
        commitEdit {
            AnnotationRenderer.drawWatermark(
                on: $0,
                text: text,
                style: style,
                scale: scale,
                fontSize: fontSize,
                color: color,
                opacity: opacity
            )
        }
        editorTool = .rect
        flashToast("已添加水印")
    }

    func beginTextInput(at point: CGPoint) {
        if showTextInput { confirmTextInput() }
        pendingTextPoint = point
        textDraft = ""
        showTextInput = true
    }

    func confirmTextInput() {
        if let point = pendingTextPoint {
            let text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                pushHistory()
                overlays.append(
                    .text(
                        at: point,
                        text: text,
                        color: annotationColor,
                        fontSize: strokePixelWidth * 6,
                        backdrop: textBackdrop,
                        backdropColor: textBackdropColor
                    )
                )
                refreshEditorPreview()
            }
        }
        showTextInput = false
        pendingTextPoint = nil
        textDraft = ""
    }

    func beginMoveOverlay() {
        pushHistory()
    }

    func moveOverlay(id: UUID, origin: CGPoint) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
        var items = overlays
        items[index].frame.origin = origin
        overlays = items
    }

    func finishMoveOverlay() {
        refreshEditorPreview()
    }

    func cancelTextInput() {
        showTextInput = false
        pendingTextPoint = nil
        textDraft = ""
    }

    func applyRedact(pixelRect: CGRect) {
        switch editorTool {
        case .mosaic:
            commitEdit { ImageRedact.applyMosaic(to: $0, rect: pixelRect) }
        case .highlight:
            pushHistory()
            highlightRects.append(pixelRect)
            refreshEditorPreview()
        case .blur:
            commitEdit {
                ImageRedact.applyBlur(
                    to: $0,
                    rect: pixelRect,
                    sigma: CGFloat(blurSigma),
                    feather: CGFloat(blurFeather)
                )
            }
        default:
            break
        }
    }

    func undoEditor() {
        guard let current = editorImage, let previous = editorUndoStack.popLast() else { return }
        editorRedoStack.append(EditorSnapshot(image: current, highlights: highlightRects, overlays: overlays))
        restore(previous)
    }

    func redoEditor() {
        guard let current = editorImage, let next = editorRedoStack.popLast() else { return }
        editorUndoStack.append(EditorSnapshot(image: current, highlights: highlightRects, overlays: overlays))
        restore(next)
    }

    func copyEditor() {
        guard let image = editorImage, let cg = image.youshotCGImage else { return }
        let styled = NSImage(youshotCGImage: styledExport(flattened(cg)))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([styled])
        lastPreview = styled
        statusMessage = "已复制到剪贴板"
        hasError = false
    }

    func saveEditor() {
        guard let image = editorImage, let cg = image.youshotCGImage else { return }
        let styled = styledExport(flattened(cg))
        do {
            try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
            let url = editorURL
                ?? saveDirectory.appendingPathComponent("YouShot-\(timestamp()).png")
            try PNGFile.write(styled, to: url)
            editorURL = url
            lastFileURL = url
            lastPreview = NSImage(youshotCGImage: styled)
            statusMessage = "已保存到 图片/YouShot"
            hasError = false
            flashToast("已保存到 图片/YouShot")
        } catch {
            statusMessage = error.localizedDescription
            hasError = true
            flashToast("保存失败")
        }
    }

    /// 完成：只复制最终图片并关闭；文件仅由下载按钮显式写入。
    func confirmEditor() {
        copyEditor()
        closeEditor()
    }

    /// 取消：恢复到进入编辑时的原图并关闭
    func cancelEditor() {
        if let base = editorBaseImage {
            editorImage = base
            highlightRects.removeAll()
            overlays.removeAll()
            lastPreview = base
        }
        closeEditor()
        statusMessage = "已取消编辑"
        hasError = false
    }

    func closeEditor() {
        AnnotationOverlay.shared.dismiss()
        editorImage = nil
        editorURL = nil
        editorBaseImage = nil
        editorBackdrop = nil
        editorBackdropCG = nil
        editorHostScreenFrame = nil
        editorSelectionFrame = nil
        overlaySelection = .zero
        overlayResizing = false
        overlayResizeOrigin = nil
        highlightRects.removeAll()
        overlays.removeAll()
        cancelTextInput()
        editorUndoStack.removeAll()
        editorRedoStack.removeAll()
        canUndoEditor = false
        canRedoEditor = false
        toastTask?.cancel()
        overlayToast = nil
    }

    /// 从菜单重新打开当前标注层（仍在冻结的整屏背景上）
    func reopenEditorOverlay() {
        guard let image = editorImage ?? lastPreview,
              let screenFrame = editorHostScreenFrame,
              let selectionFrame = editorSelectionFrame,
              let backdrop = editorBackdrop
        else { return }
        if editorImage == nil {
            editorImage = image
            editorBaseImage = image
        }
        overlaySelection = CGRect(
            x: selectionFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - selectionFrame.maxY,
            width: selectionFrame.width,
            height: selectionFrame.height
        )
        overlayResizing = false
        overlayResizeOrigin = nil
        AnnotationOverlay.shared.present(
            controller: self,
            screenFrame: screenFrame,
            selectionFrame: selectionFrame,
            backdrop: backdrop
        )
    }

    private func commitEdit(_ transform: (CGImage) -> CGImage?) {
        guard let current = editorImage, let cg = current.youshotCGImage else { return }
        guard let result = transform(cg) else { return }
        pushHistory()
        editorImage = NSImage(youshotCGImage: result)
        refreshEditorPreview()
    }

    private func pushHistory() {
        guard let image = editorImage else { return }
        editorUndoStack.append(EditorSnapshot(image: image, highlights: highlightRects, overlays: overlays))
        editorRedoStack.removeAll()
        canUndoEditor = true
        canRedoEditor = false
    }

    private func restore(_ snapshot: EditorSnapshot) {
        editorImage = snapshot.image
        highlightRects = snapshot.highlights
        overlays = snapshot.overlays
        canUndoEditor = !editorUndoStack.isEmpty
        canRedoEditor = !editorRedoStack.isEmpty
        refreshEditorPreview()
    }

    /// 把高亮遮罩与可拖动标注合入图片
    private func flattened(_ image: CGImage) -> CGImage {
        var result = image
        if !highlightRects.isEmpty {
            result = AnnotationRenderer.drawHighlight(
                on: result,
                rects: highlightRects,
                dim: CGFloat(highlightDim)
            ) ?? result
        }
        for item in overlays {
            result = item.draw(on: result) ?? result
        }
        return result
    }

    private func flashToast(_ text: String) {
        overlayToast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.overlayToast = nil
        }
    }

    /// 仅刷新内存预览；编辑过程不写入磁盘。
    private func refreshEditorPreview() {
        guard let image = editorImage, let cg = image.youshotCGImage else { return }
        let flat = flattened(cg)
        lastPreview = NSImage(youshotCGImage: flat)
    }

    private func styledExport(_ image: CGImage, scale: CGFloat? = nil) -> CGImage {
        let pixelScale = scale ?? editorPixelScale.width
        return ImageExportStyle.apply(
            image,
            cornerRadius: CGFloat(exportCornerRadius) * pixelScale,
            shadowBlur: CGFloat(exportShadowBlur) * pixelScale,
            shadowOpacity: CGFloat(exportShadowOpacity),
            shadowOffsetY: CGFloat(exportShadowBlur) * 0.35 * pixelScale
        ) ?? image
    }

    /// 拖动选区手柄后，从整屏冻结图重新裁出标注内容。
    func recropSelection(inScreen rect: CGRect) {
        guard let full = editorBackdropCG, let screenFrame = editorHostScreenFrame else { return }
        let bounds = CGRect(origin: .zero, size: screenFrame.size)
        let clamped = rect.intersection(bounds)
        guard clamped.width >= 8, clamped.height >= 8 else { return }

        editorSelectionFrame = CGRect(
            x: screenFrame.minX + clamped.minX,
            y: screenFrame.maxY - clamped.minY - clamped.height,
            width: clamped.width,
            height: clamped.height
        )

        let scaleX = CGFloat(full.width) / screenFrame.width
        let scaleY = CGFloat(full.height) / screenFrame.height
        let pixel = CGRect(
            x: clamped.minX * scaleX,
            y: clamped.minY * scaleY,
            width: clamped.width * scaleX,
            height: clamped.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard pixel.width >= 1, pixel.height >= 1, let cropped = full.cropping(to: pixel) else { return }

        let image = NSImage(youshotCGImage: cropped)
        editorUndoStack.removeAll()
        editorRedoStack.removeAll()
        canUndoEditor = false
        canRedoEditor = false
        highlightRects.removeAll()
        overlays.removeAll()
        editorBaseImage = image
        editorImage = image
        refreshEditorPreview()
    }

    private func presentEditor(
        image: NSImage,
        screenFrame: CGRect,
        selectionFrame: CGRect,
        backdrop: NSImage,
        fullImage: CGImage
    ) {
        editorUndoStack.removeAll()
        editorRedoStack.removeAll()
        canUndoEditor = false
        canRedoEditor = false
        highlightRects.removeAll()
        overlays.removeAll()
        editorBaseImage = image
        editorImage = image
        editorURL = nil
        editorBackdrop = backdrop
        editorBackdropCG = fullImage
        editorHostScreenFrame = screenFrame
        editorSelectionFrame = selectionFrame
        editorTool = .rect
        lastPreview = image
        overlaySelection = CGRect(
            x: selectionFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - selectionFrame.maxY,
            width: selectionFrame.width,
            height: selectionFrame.height
        )
        overlayResizing = false
        overlayResizeOrigin = nil
        AnnotationOverlay.shared.present(
            controller: self,
            screenFrame: screenFrame,
            selectionFrame: selectionFrame,
            backdrop: backdrop
        )
    }

    private func globalFrame(for selection: RegionSelection) -> CGRect {
        let nsScreen = screen(for: selection.displayID) ?? screenUnderMouse()
        let local = selection.displayLocalRect
        return CGRect(
            x: nsScreen.frame.minX + local.minX,
            y: nsScreen.frame.maxY - local.minY - local.height,
            width: local.width,
            height: local.height
        )
    }

    // MARK: - Capture flow

    private func runCapture(mode: CaptureMode) async {
        do {
            let results: [CaptureResult]
            switch mode {
            case .currentDisplay:
                try await runDelay(on: screenUnderMouse())
                results = [try await captureDisplay(screenUnderMouse())]
            case .allDisplays:
                try await runDelay(on: screenUnderMouse())
                results = try await captureAllDisplays()
            case .region:
                // 在任何选区面板出现前冻结所有屏幕。菜单、Popover、Spotlight、
                // Raycast 等失焦即消失的界面仍会留在冻结帧里供选择和裁剪。
                let context = try await makeRegionCaptureContext()
                guard let selection = await regionSelector.pick(
                    snapWindows: windowSnapEnabled,
                    frozenFrames: context.frames
                ) else {
                    throw CancellationError()
                }
                try Task.checkCancellation()
                let delayScreen = screen(for: selection.displayID) ?? screenUnderMouse()
                try await runDelay(on: delayScreen)
                let captured = try await captureRegionOnFrozenScreen(
                    selection,
                    context: context,
                    useTriggerFrame: delaySeconds == 0
                )
                lastPreview = captured.regionImage
                finishIdle(message: "标注后点绿色勾复制，点下载保存文件")
                presentEditor(
                    image: captured.regionImage,
                    screenFrame: captured.screen.frame,
                    selectionFrame: globalFrame(for: selection),
                    backdrop: captured.backdrop,
                    fullImage: captured.fullImage
                )
                // 标注层已覆盖在冻结画面上后再撤掉选区层，避免松开鼠标时闪回原画面。
                // 标注层已经接管指针语义，不要用箭头覆盖它刚设置的工具/缩放指针。
                regionSelector.dismiss(restoreCursor: false)
                return
            }

            guard let first = results.first else {
                throw CaptureError.noDisplay
            }
            lastFileURL = first.url
            let preview = NSImage(contentsOf: first.url)
            lastPreview = preview
            copyFileToPasteboard(first.url)
            let message: String
            if results.count == 1 {
                message = "已保存 \(first.pixelWidth)×\(first.pixelHeight) PNG，并已复制到剪贴板"
            } else {
                message = "已保存 \(results.count) 张屏幕截图，剪贴板为指针所在屏"
            }
            finishIdle(message: message)
        } catch is CancellationError {
            hud.close()
            regionSelector.dismiss()
            finishIdle(message: "已取消")
        } catch {
            hud.close()
            regionSelector.dismiss()
            hasError = true
            finishIdle(message: error.localizedDescription)
        }
    }

    private func runDelay(on screen: NSScreen) async throws {
        if delaySeconds > 0 {
            for remaining in stride(from: delaySeconds, through: 1, by: -1) {
                try Task.checkCancellation()
                remainingSeconds = remaining
                hud.show(seconds: remaining, on: screen)
                try await Task.sleep(for: .seconds(1))
            }
        }
        try Task.checkCancellation()
        remainingSeconds = 0
        hud.close()
        try await Task.sleep(for: .milliseconds(150))
        try Task.checkCancellation()
    }

    private func finishIdle(message: String) {
        remainingSeconds = 0
        setBusy(false)
        statusMessage = message
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        onEscapeCancelEnabled?(busy)
    }

    private var saveDirectory: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YouShot", isDirectory: true)
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            self.displayID(of: $0) == displayID
        }
    }

    private func copyFileToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        if let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image])
        }
    }

    private func captureAllDisplays() async throws -> [CaptureResult] {
        let content = try await shareableContent()
        let mouseScreen = screenUnderMouse()
        let mouseID = displayID(of: mouseScreen)
        var results: [CaptureResult] = []
        let stamp = timestamp()
        var index = 1
        for screen in NSScreen.screens {
            let id = displayID(of: screen)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let result = try await capture(
                display: display,
                content: content,
                sourceRect: nil,
                fileName: "YouShot-\(stamp)-\(index).png"
            )
            if id == mouseID {
                results.insert(result, at: 0)
            } else {
                results.append(result)
            }
            index += 1
        }
        if results.isEmpty { throw CaptureError.noDisplay }
        return results
    }

    private func captureDisplay(_ screen: NSScreen) async throws -> CaptureResult {
        let content = try await shareableContent()
        let id = displayID(of: screen)
        guard let display = content.displays.first(where: { $0.displayID == id })
                ?? content.displays.first
        else {
            throw CaptureError.noDisplay
        }
        return try await capture(
            display: display,
            content: content,
            sourceRect: nil,
            fileName: "YouShot-\(timestamp()).png"
        )
    }

    /// 使用整屏冻结图作为操作区背景，并在零延迟时从同一张图裁出选区保存。
    private func captureRegionOnFrozenScreen(
        _ selection: RegionSelection,
        context: RegionCaptureContext,
        useTriggerFrame: Bool
    ) async throws -> RegionCaptureBundle {
        let nsScreen = screen(for: selection.displayID) ?? screenUnderMouse()
        let content: SCShareableContent
        let rawFull: CGImage
        if useTriggerFrame, let frozen = context.frames[selection.displayID] {
            content = context.content
            rawFull = frozen
        } else {
            content = try await shareableContent()
            guard let display = content.displays.first(where: { $0.displayID == selection.displayID })
                    ?? content.displays.first
            else {
                throw CaptureError.noDisplay
            }
            // Cursor is composited from the trigger-time snapshot below. This keeps
            // its original arrow/I-beam/etc. instead of capturing the selection
            // overlay's crosshair.
            rawFull = try await captureImage(
                display: display,
                content: content,
                sourceRect: nil,
                showsCursor: false
            )
        }
        let scaleX = CGFloat(rawFull.width) / nsScreen.frame.width
        let scaleY = CGFloat(rawFull.height) / nsScreen.frame.height
        let pixelRect = CGRect(
            x: selection.displayLocalRect.minX * scaleX,
            y: selection.displayLocalRect.minY * scaleY,
            width: selection.displayLocalRect.width * scaleX,
            height: selection.displayLocalRect.height * scaleY
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: rawFull.width, height: rawFull.height))
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let regionCrop = rawFull.cropping(to: pixelRect)
        else {
            throw CaptureError.noDisplay
        }
        // 吸附到窗口时单独采集该窗口，圆角外为透明，避免把窗口投影一起截进来
        let rawCrop = await captureWindowImage(selection.windowID, content: content) ?? regionCrop
        let cropped = drawCursor(
            context.cursor,
            onto: rawCrop,
            screen: nsScreen,
            displayLocalRect: selection.displayLocalRect
        )
        let fullRect = CGRect(origin: .zero, size: nsScreen.frame.size)
        let full = drawCursor(
            context.cursor,
            onto: rawFull,
            screen: nsScreen,
            displayLocalRect: fullRect
        )

        return RegionCaptureBundle(
            regionImage: NSImage(youshotCGImage: cropped),
            backdrop: NSImage(cgImage: full, size: nsScreen.frame.size),
            fullImage: full,
            screen: nsScreen
        )
    }

    /// 触发瞬间建立区域截图上下文。必须在选区面板创建前执行，避免临时窗口
    /// 因 key window 或鼠标点击变化而消失。单屏失败不会拖累其他显示器，选中
    /// 缺失帧的屏幕时会回退到常规实时采集。
    private func makeRegionCaptureContext() async throws -> RegionCaptureContext {
        let cursor = captureCursorSnapshot()
        let content = try await shareableContent(onScreenWindowsOnly: true)
        var frames: [CGDirectDisplayID: CGImage] = [:]

        for screen in NSScreen.screens {
            try Task.checkCancellation()
            let id = displayID(of: screen)
            guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            if let image = try? await captureImage(
                display: display,
                content: content,
                sourceRect: nil,
                showsCursor: false
            ) {
                frames[id] = image
            }
        }
        return RegionCaptureContext(content: content, frames: frames, cursor: cursor)
    }

    private func capture(
        display: SCDisplay,
        content: SCShareableContent,
        sourceRect: CGRect?,
        fileName: String
    ) async throws -> CaptureResult {
        let image = try await captureImage(display: display, content: content, sourceRect: sourceRect)
        let scale = CGFloat(
            NSScreen.screens.first { displayID(of: $0) == display.displayID }?.backingScaleFactor ?? 2
        )
        let exported = styledExport(image, scale: scale)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        let url = saveDirectory.appendingPathComponent(fileName)
        try PNGFile.write(exported, to: url)
        return CaptureResult(url: url, pixelWidth: exported.width, pixelHeight: exported.height)
    }

    /// 按窗口采集：背景透明、不含系统投影。
    private func captureWindowImage(_ windowID: CGWindowID?, content: SCShareableContent) async -> CGImage? {
        guard let windowID,
              let window = content.windows.first(where: { $0.windowID == windowID })
        else {
            return nil
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        config.shouldBeOpaque = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    private func captureImage(
        display: SCDisplay,
        content: SCShareableContent,
        sourceRect: CGRect?,
        showsCursor: Bool? = nil
    ) async throws -> CGImage {
        // 排除 YouShot 自己的截图遮罩/HUD/标注层，但把当前可见的正常设置窗口加回。
        // 这样既不会把操作层截进去，也能对 YouShot 设置页做整屏、区域或窗口截图。
        let ownBundleIDs = Set(
            [Bundle.main.bundleIdentifier, "top.yayalu.youshot"]
                .compactMap { $0 }
        )
        let selfApps = content.applications.filter { ownBundleIDs.contains($0.bundleIdentifier) }
        let capturableSelfWindowIDs = Set(
            NSApp.windows.compactMap { window -> CGWindowID? in
                guard window.isVisible,
                      window.alphaValue > 0.01,
                      window.sharingType != .none,
                      window.styleMask.contains(.titled)
                else {
                    return nil
                }
                return CGWindowID(window.windowNumber)
            }
        )
        let capturableSelfWindows = content.windows.filter {
            capturableSelfWindowIDs.contains($0.windowID)
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: selfApps,
            exceptingWindows: capturableSelfWindows
        )
        let scale = CGFloat(filter.pointPixelScale)
        let config = SCStreamConfiguration()
        if let sourceRect {
            config.sourceRect = sourceRect
            config.width = Int((sourceRect.width * scale).rounded())
            config.height = Int((sourceRect.height * scale).rounded())
        } else {
            config.width = Int((filter.contentRect.width * scale).rounded())
            config.height = Int((filter.contentRect.height * scale).rounded())
        }
        config.showsCursor = showsCursor ?? includeCursor
        config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.captureResolution = .best
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    private func captureCursorSnapshot() -> CursorSnapshot? {
        guard includeCursor else { return nil }
        let cursor = NSCursor.current
        let image = cursor.image
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return CursorSnapshot(
            image: cgImage,
            size: image.size,
            hotSpot: cursor.hotSpot,
            globalLocation: NSEvent.mouseLocation
        )
    }

    /// Draw a trigger-time AppKit cursor into an image whose coordinate space
    /// corresponds to `displayLocalRect` (display-local points, top-left origin).
    private func drawCursor(
        _ cursor: CursorSnapshot?,
        onto image: CGImage,
        screen: NSScreen,
        displayLocalRect: CGRect
    ) -> CGImage {
        guard let cursor else { return image }

        let cursorInDisplayTopLeft = CGPoint(
            x: cursor.globalLocation.x - screen.frame.minX,
            y: screen.frame.maxY - cursor.globalLocation.y
        )
        guard displayLocalRect.width > 0, displayLocalRect.height > 0 else { return image }
        let scaleX = CGFloat(image.width) / displayLocalRect.width
        let scaleY = CGFloat(image.height) / displayLocalRect.height
        let selectionBottom = screen.frame.height - displayLocalRect.maxY
        let cursorBottom = cursor.globalLocation.y - screen.frame.minY
        let cursorRect = CGRect(
            x: (cursorInDisplayTopLeft.x - displayLocalRect.minX - cursor.hotSpot.x) * scaleX,
            // NSCursor hot spots use a flipped, top-left origin. Convert the
            // vertical offset before drawing into Core Graphics' bottom-left
            // coordinate system.
            y: (
                cursorBottom - selectionBottom
                    - (cursor.size.height - cursor.hotSpot.y)
            ) * scaleY,
            width: cursor.size.width * scaleX,
            height: cursor.size.height * scaleY
        )
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        // Cropping a pre-composited full-screen image keeps the visible part of
        // a cursor that straddles an edge, so mirror that behavior here.
        guard cursorRect.intersects(imageRect),
              let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return image }

        context.draw(image, in: imageRect)
        context.interpolationQuality = .high
        context.draw(cursor.image, in: cursorRect)
        return context.makeImage() ?? image
    }

    private func shareableContent(onScreenWindowsOnly: Bool = false) async throws -> SCShareableContent {
        if !CGPreflightScreenCaptureAccess() {
            throw CaptureError.permissionDenied
        }
        do {
            // 区域选取层会保留到冻结截图完成。目标窗口此时可能被全屏遮罩完全覆盖，
            // 因此需要包含全部窗口，才能继续按 windowID 完成透明窗口采集。
            return try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: onScreenWindowsOnly
            )
        } catch {
            throw CaptureError.permissionDenied
        }
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        UInt32(
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        )
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

/// 撤销/重做的一步：图片内容 + 高亮遮罩 + 可拖动标注
private struct EditorSnapshot {
    let image: NSImage
    let highlights: [CGRect]
    let overlays: [OverlayItem]
}

private struct CaptureResult {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
}

private struct CursorSnapshot {
    let image: CGImage
    let size: CGSize
    let hotSpot: CGPoint
    let globalLocation: CGPoint
}

private struct RegionCaptureContext {
    let content: SCShareableContent
    let frames: [CGDirectDisplayID: CGImage]
    let cursor: CursorSnapshot?
}

private struct RegionCaptureBundle {
    let regionImage: NSImage
    let backdrop: NSImage
    let fullImage: CGImage
    let screen: NSScreen
}

private enum CaptureError: LocalizedError {
    case noDisplay
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "没有可用的显示器"
        case .permissionDenied:
            return "未获得屏幕录制权限，请在系统设置中授权后重试"
        }
    }
}

@MainActor
private final class CountdownHUD {
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")

    func show(seconds: Int, on screen: NSScreen) {
        label.stringValue = "\(seconds)"
        label.font = .monospacedDigitSystemFont(ofSize: 64, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false

        if panel == nil {
            let box = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 140))
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
            box.layer?.cornerRadius = 20
            label.frame = box.bounds.insetBy(dx: 8, dy: 8)
            box.addSubview(label)

            let created = CountdownPanel(
                contentRect: box.bounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.isFloatingPanel = true
            created.level = .statusBar
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = false
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            created.sharingType = .none
            created.contentView = box
            panel = created
        }

        guard let panel else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            )
        )
        panel.orderFrontRegardless()
        // 不激活 YouShot，也不抢键盘焦点。这样目标 App 的失焦即关闭面板
        // （例如部分“设置”窗口）会在倒计时期间保持可见；Esc 由全局热键处理。
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class CountdownPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}
