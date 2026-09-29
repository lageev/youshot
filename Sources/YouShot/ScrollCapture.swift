import AppKit
import SwiftUI

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

/// 只保留首帧和每次新出现的条带，避免长期持有所有完整帧。
final class ScrollCaptureStitcher {
    private let width: Int
    private let viewportHeight: Int
    private let maxHeight: Int
    private let colorSpace: CGColorSpace
    private var pieces: [CGImage]
    private(set) var pixelHeight: Int
    private(set) var frameCount = 1
    private var previousFrame: CGImage
    private var previousProfile: RowProfile?
    /// 底部悬浮条（工具栏、Cookie 提示等）高度，首次拼接时确定。新条带从它上方截取，
    /// 成品末尾再补一次，避免悬浮条在长图中间反复出现。
    private var fixedBottom: Int?
    /// 每次拼接都没变化的列（侧栏等），以及其中一行空白作为分割行。长图里静止区域
    /// 分割行以上取首帧、以下取末帧贴底，中间用分割行拉伸，避免每个条带重复一遍。
    private var staticColumns: [Bool]?
    private var staticSplit: Int?

    init(firstFrame: CGImage, maxHeight: Int) {
        width = firstFrame.width
        viewportHeight = firstFrame.height
        self.maxHeight = max(maxHeight, firstFrame.height)
        colorSpace = firstFrame.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        pieces = [firstFrame]
        pixelHeight = firstFrame.height
        previousFrame = firstFrame
        previousProfile = RowProfile(firstFrame)
    }

    func append(_ currentFrame: CGImage, expectedShiftPixels: CGFloat) -> ScrollAppendOutcome {
        guard currentFrame.width == width, currentFrame.height == viewportHeight,
              let previousProfile,
              let currentProfile = RowProfile(currentFrame)
        else {
            return .stalled
        }
        guard !Self.imagesAreNearlyIdentical(previousFrame, currentFrame) else {
            return .stalled
        }
        guard let match = RowProfile.match(previousProfile, currentProfile, expected: expectedShiftPixels) else {
            return .stalled
        }

        let remaining = maxHeight - pixelHeight
        guard remaining > 0 else { return .heightLimitReached }
        if fixedBottom == nil {
            fixedBottom = 0
            // 窗口底部圆角、滚动边缘渐隐只出现在视口最底部，未检测到悬浮条时也预留一段，
            // 否则会随每个条带重复出现在长图中间。
            let bottom = max(match.fixedBottom, viewportHeight / 10)
            let bodyRect = CGRect(x: 0, y: 0, width: width, height: viewportHeight - bottom)
            if let body = pieces[0].cropping(to: bodyRect) {
                pieces[0] = body
                fixedBottom = bottom
            }
            staticSplit = previousProfile.flatRow(
                in: match.staticColumns,
                rows: max(1, match.fixedTop)..<(viewportHeight - (fixedBottom ?? 0))
            )
        }
        // 新内容紧接在上一帧内容之后：当前帧 [stripBottom - shift, stripBottom)。
        let stripBottom = viewportHeight - (fixedBottom ?? 0)
        let stripTop = stripBottom - match.shift
        let newRows = min(match.shift, remaining)
        guard newRows >= 4, stripTop >= match.fixedTop else { return .stalled }

        // CGImage 的裁剪坐标以图片左上为原点。
        let stripRect = CGRect(x: 0, y: stripTop, width: width, height: newRows)
        guard let borrowed = currentFrame.cropping(to: stripRect),
              let strip = Self.renderCopy(borrowed, colorSpace: colorSpace)
        else {
            return .stalled
        }

        pieces.append(strip)
        pixelHeight += newRows
        frameCount += 1
        previousFrame = currentFrame
        self.previousProfile = currentProfile
        staticColumns = zip(staticColumns ?? match.staticColumns, match.staticColumns).map { $0 && $1 }
        return pixelHeight >= maxHeight ? .heightLimitReached : .appended(newRows: newRows)
    }

    /// 底部悬浮条取自最后一帧，这样即使把最后一屏底部的真实内容误判成悬浮条也不会丢失。
    private var footer: [CGImage] {
        guard let fixedBottom, fixedBottom > 0,
              let image = previousFrame.cropping(
                  to: CGRect(x: 0, y: viewportHeight - fixedBottom, width: width, height: fixedBottom)
              )
        else { return [] }
        return [image]
    }

    func makeImage() -> CGImage? {
        guard let context = Self.makeContext(width: width, height: pixelHeight, colorSpace: colorSpace) else {
            return nil
        }
        var usedHeight = 0
        for piece in pieces + footer {
            let y = pixelHeight - usedHeight - piece.height
            context.draw(piece, in: CGRect(x: 0, y: y, width: piece.width, height: piece.height))
            usedHeight += piece.height
        }
        drawStaticColumns(in: context, scaleX: 1, scaleY: 1)
        return context.makeImage()
    }

    private func drawStaticColumns(in context: CGContext, scaleX: CGFloat, scaleY: CGFloat) {
        guard frameCount > 1, let staticSplit, let staticColumns, let previousProfile else { return }
        let bottomHeight = CGFloat(viewportHeight - staticSplit)
        let fillHeight = CGFloat(pixelHeight) - CGFloat(staticSplit) - bottomHeight
        for range in previousProfile.pixelRanges(of: staticColumns) {
            let x = CGFloat(range.lowerBound)
            let width = CGFloat(range.count)
            guard let fill = previousFrame.cropping(to: CGRect(x: x, y: CGFloat(staticSplit), width: width, height: 1)),
                  let bottom = previousFrame.cropping(
                      to: CGRect(x: x, y: CGFloat(staticSplit), width: width, height: bottomHeight)
                  )
            else { continue }
            // 上下文原点在左下：末帧分割行以下贴底，其上用分割行拉伸到首帧分割行处。
            context.draw(bottom, in: CGRect(x: x * scaleX, y: 0, width: width * scaleX, height: bottomHeight * scaleY))
            context.draw(
                fill,
                in: CGRect(x: x * scaleX, y: bottomHeight * scaleY, width: width * scaleX, height: fillHeight * scaleY)
            )
        }
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
        for piece in pieces + footer {
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
        drawStaticColumns(
            in: context,
            scaleX: CGFloat(previewWidth) / CGFloat(width),
            scaleY: CGFloat(previewHeight) / CGFloat(pixelHeight)
        )
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

/// 帧的灰度行轮廓：每行横向压缩成固定列数，逐行比对即可求出两帧的垂直位移。
/// 每个候选位移都要在整段重叠区校验通过，重复或空白内容不会像纯配准那样被误拼。
private struct RowProfile {
    struct Match {
        let shift: Int
        /// 两帧同位置保持不变的顶部 / 底部行数，即粘性顶栏和底部悬浮条。
        let fixedTop: Int
        let fixedBottom: Int
        /// 两帧间整列没变化的列。
        let staticColumns: [Bool]
    }

    static let columns = 128

    let usableWidth: Int
    let rows: Int
    let values: [UInt8]
    /// 行内有明暗变化（文字、图形）。
    let textured: [Bool]
    /// 与上一行明显不同。只有这类行能确定垂直位置，纯色块内部上下移动几像素看不出差别。
    let edges: [Bool]

    init?(_ image: CGImage) {
        // 去掉右侧滚动条：叠加式滚动条只在滚动时出现，会干扰比对。
        let usableWidth = image.width - max(8, image.width / 25)
        guard usableWidth >= Self.columns, image.height >= 80,
              let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: usableWidth, height: image.height))
        else { return nil }

        let columns = Self.columns
        let rows = image.height
        var values = [UInt8](repeating: 0, count: rows * columns)
        let drawn = values.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: columns,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: columns,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            return true
        }
        guard drawn else { return nil }

        var textured = [Bool](repeating: false, count: rows)
        var edges = [Bool](repeating: false, count: rows)
        for r in 0..<rows {
            let base = r * columns
            var horizontal = 0
            var vertical = 0
            for k in 0..<columns {
                if k > 0 { horizontal += abs(Int(values[base + k]) - Int(values[base + k - 1])) }
                if r > 0 { vertical += abs(Int(values[base + k]) - Int(values[base + k - columns])) }
            }
            textured[r] = horizontal > columns * 2
            edges[r] = vertical > columns * 2
        }
        self.usableWidth = usableWidth
        self.rows = rows
        self.values = values
        self.textured = textured
        self.edges = edges
    }

    /// `expected` 为自动滚动的预期位移像素；手动滚动传 0，多个同样吻合的位移取最小的。
    static func match(_ previous: RowProfile, _ current: RowProfile, expected: CGFloat) -> Match? {
        guard previous.rows == current.rows else { return nil }
        let rows = previous.rows
        let columns = Self.columns
        let p = previous.values
        let c = current.values

        // 整列都没变化的是侧栏等静止区域，不参与比对，否则会拉高正确位移的误差。
        let moving = (0..<columns).filter { k in
            var diff = 0
            for r in 0..<rows { diff += abs(Int(p[r * columns + k]) - Int(c[r * columns + k])) }
            return diff > rows / 2
        }
        guard moving.count >= 4 else { return nil }
        let staticColumns = (0..<columns).map { !moving.contains($0) }

        // 平均灰度差不超过 meanTolerance，且没有任何一列差超过 40。文字不同只会让少数列
        // 明显变化，单看平均值会被摊薄；渲染噪声则是各列都只差一点。
        func rowsMatch(_ pr: Int, _ cr: Int, meanTolerance: Int) -> Bool {
            let limit = meanTolerance * moving.count
            var diff = 0
            for k in moving {
                let d = abs(Int(p[pr * columns + k]) - Int(c[cr * columns + k]))
                if d > 40 { return false }
                diff += d
                if diff > limit { return false }
            }
            return true
        }

        // 从上下边缘向内找同位置不变的行（粘性顶栏、底部悬浮条）。整段都是空白时
        // 只是巧合相同，不当作固定栏。content 为截到最后一行有内容处的长度。
        func fixedRun(_ indices: StrideThrough<Int>) -> (full: Int, content: Int) {
            var length = 0
            var content = 0
            var hasText = false
            for r in indices {
                guard rowsMatch(r, r, meanTolerance: 1) else { break }
                length += 1
                hasText = hasText || previous.textured[r]
                if previous.textured[r] || previous.edges[r] { content = length }
            }
            return hasText ? (length, content) : (0, 0)
        }

        // previous 的第 pr 行对应 current 的第 pr - shift 行，只比对 [top, bottom) 之间的行。
        func search(top: Int, bottom: Int) -> Int? {
            let band = bottom - top
            var maxShift = band - max(32, band / 6)
            if expected > 0 {
                // 最后一小步可能远小于设置值，因此只限制异常偏大的结果。
                maxShift = min(maxShift, Int(expected * 1.9))
            }
            guard maxShift >= 4 else { return nil }

            // 逐行比对重叠区里有内容的行并按错行比例打分，大块纯色不会把少数错位行摊薄；
            // 允许一定比例的错行以容忍动图、悬浮动画。goodEdges 为对上的边缘行数，
            // 没有边缘时纯色块内部上下错几像素也看不出来。
            let maxBadRatio = 0.35
            func score(_ shift: Int, step: Int, maxBad: Double) -> (bad: Int, goodEdges: Int, compared: Int)? {
                let badLimit = Int(maxBad * Double((band - shift + step - 1) / step))
                var bad = 0
                var goodEdges = 0
                var compared = 0
                var pr = top + shift
                while pr < bottom {
                    let cr = pr - shift
                    if previous.textured[pr] || previous.edges[pr] || current.textured[cr] || current.edges[cr] {
                        compared += 1
                        if !rowsMatch(pr, cr, meanTolerance: 4) {
                            bad += 1
                            if bad > badLimit { return nil }
                        } else if previous.edges[pr] || current.edges[cr] {
                            goodEdges += 1
                        }
                    }
                    pr += step
                }
                return (bad, goodEdges, compared)
            }

            var shifts = Array(4...maxShift)
            if expected > 0 {
                let target = Int(expected.rounded())
                shifts.sort { abs($0 - target) < abs($1 - target) }
            }

            // 先隔行粗筛，再对粗筛靠前的位移及其相邻值逐行复核。
            var bestCoarse = maxBadRatio
            var coarse: [(shift: Int, bad: Double)] = []
            for shift in shifts {
                guard let result = score(shift, step: 2, maxBad: min(maxBadRatio, bestCoarse + 0.05)),
                      result.compared > 0
                else { continue }
                let bad = Double(result.bad) / Double(result.compared)
                coarse.append((shift, bad))
                bestCoarse = min(bestCoarse, bad)
            }

            var candidates = Set<Int>()
            for item in coarse where item.bad <= bestCoarse + 0.05 {
                for shift in item.shift - 1...item.shift + 1 where shift >= 4 && shift <= maxShift {
                    candidates.insert(shift)
                }
            }
            let fine = candidates.compactMap { shift -> (shift: Int, bad: Double)? in
                guard let result = score(shift, step: 1, maxBad: maxBadRatio),
                      result.goodEdges >= 2, result.compared - result.bad >= 8
                else { return nil }
                return (shift, Double(result.bad) / Double(result.compared))
            }

            if let bestFine = fine.map(\.bad).min() {
                let near = fine.filter { $0.bad <= bestFine + 0.002 }
                let chosen = expected > 0
                    ? near.min { abs(Double($0.shift) - expected) < abs(Double($1.shift) - expected) }
                    : near.min { $0.shift < $1.shift }
                guard let chosen else { return nil }
                return chosen.shift
            }

            // 自动滚动时重叠区内容太少、无从确认，只要与已发送的滚动量不矛盾就信任它。
            let target = Int(expected.rounded())
            if expected > 0, target >= 4, target <= maxShift,
               score(target, step: 1, maxBad: 0) != nil {
                return target
            }
            return nil
        }

        let topRun = fixedRun(stride(from: 0, through: rows * 45 / 100, by: 1))
        let bottomRun = fixedRun(stride(from: rows - 1, through: rows * 65 / 100, by: -1))
        if let shift = search(top: topRun.full, bottom: rows - bottomRun.full) {
            return Match(
                shift: shift,
                fixedTop: topRun.full,
                fixedBottom: bottomRun.full,
                staticColumns: staticColumns
            )
        }
        // 固定栏旁巧合相同的空白行也会被算进静止区、压缩可比对范围，收窄到有内容处再试一次。
        guard topRun.content < topRun.full || bottomRun.content < bottomRun.full,
              let shift = search(top: topRun.content, bottom: rows - bottomRun.content)
        else { return nil }
        return Match(
            shift: shift,
            fixedTop: topRun.content,
            fixedBottom: bottomRun.content,
            staticColumns: staticColumns
        )
    }

    /// 静止列里最长一段空白行（上下、左右都没有明暗变化）的中间行，
    /// 在这里切开静止区域不会截断侧栏条目。
    func flatRow(in mask: [Bool], rows range: Range<Int>) -> Int? {
        let columns = Self.columns
        let count = mask.filter { $0 }.count
        guard count > 0, !range.isEmpty else { return nil }

        var best = 0..<0
        var start = range.lowerBound
        for r in range {
            var cost = 0
            for k in 0..<columns where mask[k] {
                let v = Int(values[r * columns + k])
                cost += abs(v - Int(values[(r - 1) * columns + k]))
                if k > 0, mask[k - 1] { cost += abs(v - Int(values[r * columns + k - 1])) }
            }
            guard cost <= count * 2 else {
                start = r + 1
                continue
            }
            if r + 1 - start > best.count { best = start..<(r + 1) }
        }
        return best.count >= 2 ? best.lowerBound + best.count / 2 : nil
    }

    /// 把列掩码换算成原图横向像素区间，相邻的列合并成一段。
    func pixelRanges(of mask: [Bool]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var k = 0
        while k < Self.columns {
            guard mask[k] else { k += 1; continue }
            let first = k
            while k < Self.columns, mask[k] { k += 1 }
            ranges.append(first * usableWidth / Self.columns..<k * usableWidth / Self.columns)
        }
        return ranges
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
            contentRect: CGRect(x: 0, y: 0, width: 470, height: 48),
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
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.frame = effect.bounds
        stack.autoresizingMask = [.width, .height]
        info.alignment = .center
        info.lineBreakMode = .byTruncatingTail
        info.setContentHuggingPriority(.defaultLow, for: .horizontal)
        info.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        // 固定在选区右侧；右侧放不下时退到屏幕右侧内沿。预览窗口属于 YouShot，
        // 采集过滤器会排除它，因此即使视觉上覆盖选区也不会进入成品。
        xPosition = screen.visibleFrame.maxX - captureRect.maxX >= 210
            ? captureRect.maxX + 12
            : screen.visibleFrame.maxX - 202
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
        created.titleVisibility = .hidden
        created.isMovableByWindowBackground = true
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
    private var keptHeight: Int {
        max(1, Int(pixelSize.height) - Int(topTrim.rounded()) - Int(bottomTrim.rounded()))
    }

    var body: some View {
        HStack(spacing: 0) {
            preview
            Divider()
            inspector.frame(width: 268)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 720, minHeight: 560)
    }

    private var preview: some View {
        GeometryReader { proxy in
            let width = min(image.size.width, max(160, proxy.size.width - 80))
            let height = width * image.size.height / max(image.size.width, 1)
            ScrollView(.vertical) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
                    .overlay(alignment: .top) {
                        cropShade(height: CGFloat(topTrim / max(Double(pixelSize.height), 1)) * height, edge: .bottom)
                    }
                    .overlay(alignment: .bottom) {
                        cropShade(height: CGFloat(bottomTrim / max(Double(pixelSize.height), 1)) * height, edge: .top)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
                    .padding(.horizontal, 40)
                    .padding(.top, 56)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("长截图已完成")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(verbatim: "原图 \(Int(pixelSize.width)) × \(Int(pixelSize.height)) px")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("裁剪")
                    Spacer()
                    Button("重置") {
                        topTrim = 0
                        bottomTrim = 0
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tint)
                    .disabled(topTrim == 0 && bottomTrim == 0)
                }
                card {
                    trimControl(title: "顶部", value: $topTrim)
                    cardDivider
                    trimControl(title: "底部", value: $bottomTrim)
                }
                Text("压暗的部分不会导出，可用来去掉首尾多余的内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("输出")
                card {
                    infoRow("尺寸", "\(Int(pixelSize.width)) × \(keptHeight) px")
                    cardDivider
                    infoRow("格式", "PNG")
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button { onSave(croppedImage()) } label: {
                    Label("保存 PNG", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: [.command])
                HStack(spacing: 8) {
                    Button { onCopy(croppedImage()) } label: {
                        Label("复制", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut("c", modifiers: [.command])
                    Button { onClose() } label: {
                        Text("完成").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.top, 40)
        .padding(.bottom, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.86))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// 遮罩一侧的描边标出裁剪线：顶部遮罩画在下沿，底部遮罩画在上沿。
    private func cropShade(height: CGFloat, edge: Alignment) -> some View {
        Rectangle()
            .fill(.black.opacity(0.5))
            .frame(height: max(0, height))
            .overlay(alignment: edge) {
                Rectangle().fill(Color.accentColor).frame(height: height > 0 ? 2 : 0)
            }
            .allowsHitTesting(false)
    }

    private func trimControl(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(verbatim: "\(Int(value.wrappedValue.rounded())) px")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // 带 step 的 Slider 会在下方画刻度，像素级步进时密成一条黑线。
            Slider(value: value, in: 0...max(1, maxTrim))
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
