import AppKit
import SwiftUI
import Vision

enum ScrollCaptureError: LocalizedError {
    case accessibilityPermissionDenied
    case initialFrameFailed
    case stitchFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "自动长截图需要辅助功能权限来发送滚动事件，请授权后重试；手动长截图无需此权限"
        case .initialFrameFailed:
            return "未能采集滚动区域，请重新选择后重试"
        case .stitchFailed:
            return "没有找到可拼接的滚动内容，请确认选区内存在可滚动页面"
        }
    }
}

/// UI 和采集循环之间的线程安全控制器。
final class ScrollCaptureControl: @unchecked Sendable {
    enum State { case running, paused, finishing, cancelled }

    private let lock = NSLock()
    private var storedState: State = .running

    var state: State {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    @discardableResult
    func togglePause() -> State {
        lock.lock()
        defer { lock.unlock() }
        switch storedState {
        case .running: storedState = .paused
        case .paused: storedState = .running
        case .finishing, .cancelled: break
        }
        return storedState
    }

    func finish() {
        lock.lock()
        if storedState != .cancelled { storedState = .finishing }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        storedState = .cancelled
        lock.unlock()
    }
}

/// 汇总手动模式的滚轮事件。采集循环用 generation 判断是否需要抓取新帧，
/// 用 lastEventTime 判断手势是否已经停止、是否应补一张稳定帧。
final class ManualScrollTracker: @unchecked Sendable {
    struct Snapshot: Sendable {
        let generation: Int
        let lastEventTime: TimeInterval
    }

    private let lock = NSLock()
    private var generation = 0
    private var lastEventTime: TimeInterval = 0

    func noteScroll() {
        lock.lock()
        generation += 1
        lastEventTime = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(generation: generation, lastEventTime: lastEventTime)
    }
}

enum ScrollAppendOutcome {
    case appended(newRows: Int)
    case stalled
    case heightLimitReached
}

/// 只保留首帧和每次新出现的底部条带，避免长期持有所有完整帧。
final class ScrollCaptureStitcher {
    private let width: Int
    private let viewportHeight: Int
    private let maxHeight: Int
    private let colorSpace: CGColorSpace
    private var pieces: [CGImage]
    private(set) var pixelHeight: Int
    private(set) var frameCount = 1
    private var previousFrame: CGImage

    init(firstFrame: CGImage, maxHeight: Int) {
        width = firstFrame.width
        viewportHeight = firstFrame.height
        self.maxHeight = max(maxHeight, firstFrame.height)
        colorSpace = firstFrame.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        pieces = [firstFrame]
        pixelHeight = firstFrame.height
        previousFrame = firstFrame
    }

    func append(_ currentFrame: CGImage, expectedShiftPixels: CGFloat) -> ScrollAppendOutcome {
        guard currentFrame.width == width, currentFrame.height == viewportHeight else {
            return .stalled
        }
        guard !Self.imagesAreNearlyIdentical(previousFrame, currentFrame) else {
            return .stalled
        }
        guard let shift = Self.verticalShift(
            previous: previousFrame,
            current: currentFrame,
            expected: expectedShiftPixels
        ) else {
            return .stalled
        }

        let remaining = maxHeight - pixelHeight
        guard remaining > 0 else { return .heightLimitReached }
        let newRows = min(shift, remaining)
        guard newRows >= 4 else { return .stalled }

        // CGImage 的裁剪坐标以图片左上为原点；只复制当前帧底部的新内容。
        let stripRect = CGRect(
            x: 0,
            y: currentFrame.height - newRows,
            width: currentFrame.width,
            height: newRows
        )
        guard let borrowed = currentFrame.cropping(to: stripRect),
              let strip = Self.renderCopy(borrowed, colorSpace: colorSpace)
        else {
            return .stalled
        }

        pieces.append(strip)
        pixelHeight += newRows
        frameCount += 1
        previousFrame = currentFrame
        return pixelHeight >= maxHeight ? .heightLimitReached : .appended(newRows: newRows)
    }

    func makeImage() -> CGImage? {
        guard let context = Self.makeContext(width: width, height: pixelHeight, colorSpace: colorSpace) else {
            return nil
        }
        var usedHeight = 0
        for piece in pieces {
            let y = pixelHeight - usedHeight - piece.height
            context.draw(piece, in: CGRect(x: 0, y: y, width: piece.width, height: piece.height))
            usedHeight += piece.height
        }
        return context.makeImage()
    }

    /// 低分辨率合成预览，频繁刷新也不会复制整张原图。
    func makePreview(maxWidth: CGFloat = 220, maxHeight: CGFloat = 720) -> NSImage? {
        let scale = min(maxWidth / CGFloat(width), maxHeight / CGFloat(pixelHeight), 1)
        let previewWidth = max(1, Int((CGFloat(width) * scale).rounded()))
        let previewHeight = max(1, Int((CGFloat(pixelHeight) * scale).rounded()))
        guard let context = Self.makeContext(
            width: previewWidth,
            height: previewHeight,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ) else { return nil }

        var usedSourceHeight = 0
        for piece in pieces {
            let top = CGFloat(usedSourceHeight) / CGFloat(pixelHeight) * CGFloat(previewHeight)
            let bottom = CGFloat(usedSourceHeight + piece.height) / CGFloat(pixelHeight) * CGFloat(previewHeight)
            let height = max(1, bottom - top)
            context.draw(
                piece,
                in: CGRect(
                    x: 0,
                    y: CGFloat(previewHeight) - bottom,
                    width: CGFloat(previewWidth),
                    height: height
                )
            )
            usedSourceHeight += piece.height
        }
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: previewWidth, height: previewHeight))
    }

    static func imagesAreNearlyIdentical(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        guard lhs.width == rhs.width, lhs.height == rhs.height,
              let a = thumbnailBytes(lhs), let b = thumbnailBytes(rhs), a.count == b.count
        else { return false }

        var difference = 0
        var samples = 0
        for offset in stride(from: 0, to: a.count, by: 4) {
            difference += abs(Int(a[offset]) - Int(b[offset]))
            difference += abs(Int(a[offset + 1]) - Int(b[offset + 1]))
            difference += abs(Int(a[offset + 2]) - Int(b[offset + 2]))
            samples += 3
        }
        return samples > 0 && difference / samples < 2
    }

    private static func verticalShift(
        previous: CGImage,
        current: CGImage,
        expected: CGFloat
    ) -> Int? {
        let commonWidth = min(previous.width, current.width)
        let commonHeight = min(previous.height, current.height)
        guard commonWidth >= 80, commonHeight >= 80 else { return nil }

        // 分别用三种顶部裁剪深度做配准，再选最接近预期滚动量的结果。
        // 这比假定一个固定粘性栏高度更稳，能覆盖普通标题栏到大型网页导航。
        let cropX = max(2, commonWidth / 50)
        let cropBottom = commonHeight * 10 / 100
        let cropWidth = commonWidth - cropX - max(8, commonWidth / 25)
        guard cropWidth >= 60 else { return nil }

        var candidates: [Int] = []
        for topPercent in [12, 22, 32] {
            let cropTop = commonHeight * topPercent / 100
            let cropHeight = commonHeight - cropTop - cropBottom
            guard cropHeight >= 60 else { continue }
            let crop = CGRect(x: cropX, y: cropTop, width: cropWidth, height: cropHeight)
            guard let previousCrop = previous.cropping(to: crop),
                  let currentCrop = current.cropping(to: crop)
            else { continue }

            let request = VNTranslationalImageRegistrationRequest(targetedCGImage: previousCrop)
            let handler = VNImageRequestHandler(cgImage: currentCrop, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first as? VNImageTranslationAlignmentObservation
            else { continue }

            let shift = Int(observation.alignmentTransform.ty.rounded())
            guard shift >= 4, shift < commonHeight * 95 / 100 else { continue }
            if expected > 0 {
                // 最后一小步可能远小于设置值，因此只限制异常偏大的结果。
                let maximum = min(commonHeight * 94 / 100, Int(expected * 1.9))
                guard shift <= maximum else { continue }
            }
            candidates.append(shift)
        }

        guard !candidates.isEmpty else { return nil }
        let target = expected > 0 ? Int(expected.rounded()) : candidates.sorted()[candidates.count / 2]
        return candidates.min { abs($0 - target) < abs($1 - target) }
    }

    private static func thumbnailBytes(_ image: CGImage) -> [UInt8]? {
        let side = 48
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &bytes,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return bytes
    }

    private static func renderCopy(_ image: CGImage, colorSpace: CGColorSpace) -> CGImage? {
        guard let context = makeContext(width: image.width, height: image.height, colorSpace: colorSpace) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func makeContext(width: Int, height: Int, colorSpace: CGColorSpace) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

// MARK: - Capture HUD

@MainActor
final class ScrollCaptureOverlay {
    static let shared = ScrollCaptureOverlay()

    private var borderPanel: NSPanel?
    private var hudPanel: ScrollHUDPanel?
    private var previewPanel: ScrollPreviewPanel?

    func present(
        captureRect: CGRect,
        screen: NSScreen,
        control: ScrollCaptureControl,
        action: RegionCaptureAction
    ) {
        dismiss()

        let border = NSPanel(
            contentRect: captureRect.insetBy(dx: -2, dy: -2),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        border.level = .screenSaver
        border.isOpaque = false
        border.backgroundColor = .clear
        border.hasShadow = false
        border.ignoresMouseEvents = true
        border.sharingType = .none
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        border.contentView = ScrollBorderView(frame: border.contentView?.bounds ?? .zero)
        border.orderFrontRegardless()
        borderPanel = border

        let hud = ScrollHUDPanel(control: control, action: action)
        hud.position(relativeTo: captureRect, on: screen)
        hud.orderFrontRegardless()
        hudPanel = hud

        let preview = ScrollPreviewPanel(captureRect: captureRect, screen: screen)
        preview.orderFrontRegardless()
        previewPanel = preview
    }

    func update(frameCount: Int, pixelHeight: Int, maxHeight: Int, preview: NSImage?) {
        hudPanel?.update(frameCount: frameCount, pixelHeight: pixelHeight, maxHeight: maxHeight)
        if let preview { previewPanel?.update(image: preview) }
    }

    func updatePaused(_ paused: Bool) {
        hudPanel?.updatePaused(paused)
    }

    func dismiss() {
        [borderPanel, hudPanel, previewPanel].forEach { $0?.orderOut(nil) }
        borderPanel = nil
        hudPanel = nil
        previewPanel = nil
    }
}

private final class ScrollBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemGreen.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7)
        path.lineWidth = 3
        path.stroke()
    }
}

private final class ScrollHUDPanel: NSPanel {
    private let info = NSTextField(labelWithString: "准备采集…")
    private let pause = NSButton(title: "暂停", target: nil, action: nil)
    private let finish = NSButton(title: "完成", target: nil, action: nil)
    private let cancel = NSButton(title: "取消", target: nil, action: nil)
    private let control: ScrollCaptureControl
    private let modeTitle: String

    init(control: ScrollCaptureControl, action: RegionCaptureAction) {
        self.control = control
        modeTitle = action == .scrollManual ? "手动长截图" : "自动长截图"
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 350, height: 48),
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
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        contentView = effect

        info.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        info.textColor = .labelColor
        info.stringValue = action == .scrollManual ? "请在选区内缓慢滚动…" : "准备自动滚动…"
        pause.target = self
        pause.action = #selector(togglePause)
        finish.target = self
        finish.action = #selector(finishCapture)
        cancel.target = self
        cancel.action = #selector(cancelCapture)
        finish.bezelColor = .systemGreen

        let stack = NSStackView(views: [info, pause, finish, cancel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 10)
        stack.frame = effect.bounds
        stack.autoresizingMask = [.width, .height]
        info.setContentHuggingPriority(.defaultLow, for: .horizontal)
        effect.addSubview(stack)
    }

    override var canBecomeKey: Bool { false }

    func position(relativeTo rect: CGRect, on screen: NSScreen) {
        let size = frame.size
        var x = rect.midX - size.width / 2
        var y = rect.minY - size.height - 10
        if y < screen.visibleFrame.minY + 6 {
            let above = rect.maxY + 10
            y = above + size.height <= screen.visibleFrame.maxY - 6
                ? above
                : max(screen.visibleFrame.minY + 8, rect.minY + 10)
        }
        x = max(screen.visibleFrame.minX + 6, min(x, screen.visibleFrame.maxX - size.width - 6))
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    func update(frameCount: Int, pixelHeight: Int, maxHeight: Int) {
        let percent = min(100, Int(Double(pixelHeight) / Double(max(maxHeight, 1)) * 100))
        info.stringValue = "\(modeTitle) · \(frameCount) 帧 · \(pixelHeight) px · \(percent)%"
    }

    func updatePaused(_ paused: Bool) {
        pause.title = paused ? "继续" : "暂停"
    }

    @objc private func togglePause() {
        let state = control.togglePause()
        updatePaused(state == .paused)
    }

    @objc private func finishCapture() { control.finish() }
    @objc private func cancelCapture() { control.cancel() }
}

private final class ScrollPreviewPanel: NSPanel {
    private let imageView = NSImageView()
    private let anchorBottom: CGFloat
    private let targetScreen: NSScreen
    private let xPosition: CGFloat
    private let previewWidth: CGFloat = 190

    init(captureRect: CGRect, screen: NSScreen) {
        let rightSpace = screen.visibleFrame.maxX - captureRect.maxX
        let leftSpace = captureRect.minX - screen.visibleFrame.minX
        if rightSpace >= 210 {
            xPosition = captureRect.maxX + 12
        } else if leftSpace >= 210 {
            xPosition = captureRect.minX - 202
        } else {
            // 选区占满横向空间时退到屏幕右侧内沿。预览窗口属于 YouShot，
            // 采集过滤器会排除它，因此即使视觉上覆盖选区也不会进入成品。
            xPosition = screen.visibleFrame.maxX - 202
        }
        targetScreen = screen
        anchorBottom = min(
            max(screen.visibleFrame.minY + 12, captureRect.minY),
            screen.visibleFrame.maxY - 132
        )
        super.init(
            contentRect: CGRect(x: xPosition, y: anchorBottom, width: previewWidth, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.82)
        hasShadow = true
        ignoresMouseEvents = true
        sharingType = .none
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 9
        contentView?.layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTop
        imageView.frame = contentView?.bounds.insetBy(dx: 6, dy: 6) ?? .zero
        imageView.autoresizingMask = [.width, .height]
        contentView?.addSubview(imageView)
    }

    override var canBecomeKey: Bool { false }

    func update(image: NSImage) {
        imageView.image = image
        let ratio = image.size.height / max(image.size.width, 1)
        let desired = max(120, previewWidth * ratio)
        let height = min(desired, targetScreen.visibleFrame.maxY - anchorBottom - 12)
        setFrame(CGRect(x: xPosition, y: anchorBottom, width: previewWidth, height: height), display: true)
    }
}

// MARK: - Result window

@MainActor
final class ScrollCaptureResultPresenter {
    static let shared = ScrollCaptureResultPresenter()
    private var window: NSWindow?

    func present(
        image: NSImage,
        onCopy: @escaping (NSImage) -> Void,
        onSave: @escaping (NSImage) -> Void
    ) {
        window?.close()
        let view = ScrollCaptureResultView(
            image: image,
            onCopy: onCopy,
            onSave: onSave,
            onClose: { [weak self] in self?.window?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let created = NSWindow(contentViewController: hosting)
        created.title = "长截图预览"
        created.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        created.titlebarAppearsTransparent = true
        created.isReleasedWhenClosed = false
        created.minSize = NSSize(width: 720, height: 560)
        created.setContentSize(NSSize(width: 880, height: 700))
        created.center()
        created.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = created
    }
}

private struct ScrollCaptureResultView: View {
    let image: NSImage
    let onCopy: (NSImage) -> Void
    let onSave: (NSImage) -> Void
    let onClose: () -> Void

    @State private var topTrim: Double = 0
    @State private var bottomTrim: Double = 0

    private var pixelSize: CGSize {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .zero }
        return CGSize(width: cg.width, height: cg.height)
    }

    private var maxTrim: Double { max(0, Double(pixelSize.height) * 0.45) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("长截图已完成").font(.headline)
                    Text("原图 \(Int(pixelSize.width)) × \(Int(pixelSize.height)) px · 可选裁掉首尾多余区域")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("复制") { onCopy(croppedImage()) }
                    .keyboardShortcut("c", modifiers: [.command])
                Button("保存 PNG") { onSave(croppedImage()) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: [.command])
                Button("完成") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                ScrollView([.vertical, .horizontal]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(max(image.size.width, 320), 660))
                        .overlay(alignment: .top) {
                            cropShade(height: topShadeHeight)
                        }
                        .overlay(alignment: .bottom) {
                            cropShade(height: bottomShadeHeight)
                        }
                        .padding(24)
                }
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    trimControl(title: "裁掉顶部", value: $topTrim)
                    trimControl(title: "裁掉底部", value: $bottomTrim)
                    Button("重置裁剪") {
                        topTrim = 0
                        bottomTrim = 0
                    }
                    .controlSize(.small)
                    Spacer()
                    let kept = max(1, Int(pixelSize.height) - Int(topTrim) - Int(bottomTrim))
                    Text("输出尺寸\n\(Int(pixelSize.width)) × \(kept) px")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(width: 210)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private var topShadeHeight: CGFloat {
        CGFloat(topTrim / max(Double(pixelSize.height), 1)) * displayedPreviewHeight
    }

    private var bottomShadeHeight: CGFloat {
        CGFloat(bottomTrim / max(Double(pixelSize.height), 1)) * displayedPreviewHeight
    }

    private var displayedPreviewHeight: CGFloat {
        let width = min(max(image.size.width, 320), 660)
        return width * image.size.height / max(image.size.width, 1)
    }

    private func cropShade(height: CGFloat) -> some View {
        Rectangle()
            .fill(.black.opacity(0.55))
            .frame(height: max(0, height))
            .overlay(alignment: .bottom) {
                Rectangle().fill(.red).frame(height: height > 0 ? 2 : 0)
            }
            .allowsHitTesting(false)
    }

    private func trimControl(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(value.wrappedValue)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...max(1, maxTrim), step: 1)
        }
    }

    private func croppedImage() -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let top = max(0, min(cg.height - 1, Int(topTrim.rounded())))
        let bottom = max(0, min(cg.height - top - 1, Int(bottomTrim.rounded())))
        let rect = CGRect(x: 0, y: top, width: cg.width, height: cg.height - top - bottom)
        guard let cropped = cg.cropping(to: rect) else { return image }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }
}
