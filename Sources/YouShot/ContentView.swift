import AppKit
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case capture
    case annotate
    case watermark
    case export
    case hotKey
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: return "截图"
        case .annotate: return "标注"
        case .watermark: return "水印"
        case .export: return "导出"
        case .hotKey: return "快捷键"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .capture: return "camera.fill"
        case .annotate: return "pencil.tip"
        case .watermark: return "seal.fill"
        case .export: return "square.and.arrow.up"
        case .hotKey: return "keyboard"
        case .about: return "info.circle.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var controller: CaptureController
    @EnvironmentObject private var updater: UpdateController

    private let contentBG = Color(nsColor: .windowBackgroundColor)
    private let groupBG = Color.primary.opacity(0.045)

    private var tab: SettingsTab {
        SettingsTab(rawValue: controller.settingsTabRaw) ?? .capture
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)
                .background { SidebarGlassBackground() }

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(tab.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    tabContent
                }
                .padding(.horizontal, 34)
                .padding(.top, 84)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(contentBG)
        }
        // fullSizeContentView 下主动越过标题栏安全区，让左右两种材质都延伸到窗口顶部。
        // 根视图保持透明，否则 Liquid Glass 只能采样到一层实色窗口背景。
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            controller.requestPermissionIfNeeded()
        }
        .onDisappear {
            controller.stopHotKeyRecording()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(SettingsTab.allCases) { item in
                let selected = tab == item
                Button {
                    controller.settingsTabRaw = item.rawValue
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 22)
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 84)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .capture: captureTab
        case .annotate: annotateTab
        case .watermark: watermarkTab
        case .export: exportTab
        case .hotKey: hotKeyTab
        case .about: aboutTab
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var captureTab: some View {
        section("截图") {
            settingsGroup {
                settingsRow("模式") {
                    pillPicker(
                        selection: $controller.mode,
                        options: CaptureMode.allCases.map { ($0, $0.title) },
                        disabled: controller.isBusy
                    )
                }
                rowDivider
                settingsRow("倒计时") {
                    HStack(spacing: 8) {
                        pillPicker(
                            selection: delayPresetBinding,
                            options: [(0, "立即"), (3, "3秒"), (5, "5秒"), (10, "10秒")],
                            disabled: controller.isBusy
                        )
                        if ![0, 3, 5, 10].contains(controller.delaySeconds) {
                            Text("\(controller.delaySeconds) 秒")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Stepper("", value: $controller.delaySeconds, in: 0...60)
                            .labelsHidden()
                            .disabled(controller.isBusy)
                    }
                }
            }
            footnote(controller.mode == .region ? "区域模式：先选区，再倒计时截图。" : "倒计时结束后截图。")
        }

        section("选取行为") {
            settingsGroup {
                settingsRow("包含鼠标指针") {
                    Toggle("", isOn: $controller.includeCursor)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(controller.isBusy)
                }
                rowDivider
                settingsRow("窗口吸附") {
                    Toggle("", isOn: $controller.windowSnapEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(controller.isBusy)
                }
            }
            footnote("悬停高亮窗口，单击选取；拖拽自由框选。按住 ⌥ 可临时关闭吸附。")
        }

        if let message = controller.statusMessage, controller.hasError {
            section("状态") {
                settingsGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                        if !controller.hasScreenPermission {
                            Button("打开屏幕录制设置") {
                                controller.openScreenRecordingSettings()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var annotateTab: some View {
        section("画笔样式") {
            settingsGroup {
                settingsRow("颜色") {
                    PaletteSwatches(index: $controller.strokeColorIndex, customHex: $controller.strokeCustomHex, swatchSize: 16)
                }
                rowDivider
                settingsRow("粗细") {
                    compactSlider(value: $controller.strokeWidth, range: 1...16)
                }
                rowDivider
                settingsRow("笔刷") {
                    pillPicker(
                        selection: $controller.penBrush,
                        options: PenBrush.allCases.map { ($0, $0.title) }
                    )
                }
                rowDivider
                settingsRow("透明") {
                    compactSlider(value: $controller.strokeOpacity, range: 0.05...1, step: 0.05, percent: true)
                }
            }
            footnote("矩形、直线、箭头、文字共用颜色与粗细，最右侧可自定义颜色。笔刷与透明度仅用于画笔；荧光笔为正片叠底，配合半透明可手绘高亮。")
        }

        section("矩形") {
            settingsGroup {
                settingsRow("形状") {
                    pillPicker(
                        selection: $controller.rectShape,
                        options: RectShape.allCases.map { ($0, $0.title) }
                    )
                }
            }
            footnote("椭圆模式下按住 ⇧ 画正圆；圆角矩形按住 ⇧ 画正方形。")
        }

        section("文字") {
            settingsGroup {
                settingsRow("背景") {
                    pillPicker(
                        selection: $controller.textBackdrop,
                        options: TextBackdrop.allCases.map { ($0, $0.title) }
                    )
                }
                if controller.textBackdrop != .none {
                    rowDivider
                    settingsRow("背景色") {
                        PaletteSwatches(
                            index: $controller.textBackdropColorIndex,
                            customHex: $controller.textBackdropCustomHex,
                            swatchSize: 16
                        )
                    }
                }
            }
            footnote("输入框为无填充圆角描边；选定背景后，确认文字时一并画上。")
        }

        section("高亮") {
            settingsGroup {
                settingsRow("遮罩") {
                    compactSlider(value: $controller.highlightDim, range: 0.1...0.9, step: 0.05, percent: true)
                }
            }
            footnote("画出重点区域，其余部分按此深浅压暗。")
        }

        section("高斯模糊") {
            settingsGroup {
                settingsRow("强度") {
                    compactSlider(value: $controller.blurSigma, range: 4...40)
                }
                rowDivider
                settingsRow("羽化") {
                    compactSlider(value: $controller.blurFeather, range: 0...120)
                }
            }
            footnote("强度控制模糊程度；羽化为选区外柔边宽度（像素），0 为硬边。")
        }
    }

    @ViewBuilder
    private var watermarkTab: some View {
        section("水印") {
            settingsGroup {
                TextField("例如：机密 · 仅内部使用", text: $controller.watermarkText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                rowDivider
                settingsRow("颜色") {
                    PaletteSwatches(index: $controller.watermarkColorIndex, customHex: $controller.watermarkCustomHex, swatchSize: 16)
                }
                rowDivider
                settingsRow("大小") {
                    compactSlider(value: $controller.watermarkFontSize, range: 8...48)
                }
                rowDivider
                settingsRow("透明") {
                    compactSlider(value: $controller.watermarkOpacity, range: 0.05...1, step: 0.05, percent: true)
                }
                rowDivider
                settingsRow("样式") {
                    Picker("", selection: $controller.watermarkStyle) {
                        ForEach(WatermarkStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            footnote("在标注层选择水印工具后点「应用」，叠加到整个截图区域。")
        }
    }

    @ViewBuilder
    private var exportTab: some View {
        section("导出外观") {
            settingsGroup {
                settingsRow("圆角") {
                    compactSlider(value: $controller.exportCornerRadius, range: 0...28)
                }
                rowDivider
                settingsRow("阴影") {
                    compactSlider(value: $controller.exportShadowBlur, range: 0...36)
                }
                rowDivider
                settingsRow("深浅") {
                    compactSlider(value: $controller.exportShadowOpacity, range: 0...0.8, step: 0.05, percent: true)
                }
            }
            footnote("最终 PNG 使用透明底，圆角和阴影加在图片实际边缘。")
        }

        if controller.lastFileURL != nil {
            section("最近截图") {
                settingsGroup {
                    HStack(spacing: 12) {
                        if let preview = controller.lastPreview {
                            Image(nsImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        Button("在 Finder 中显示") {
                            controller.revealLastFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        if controller.hasEditor {
                            Button("回到标注层") {
                                controller.reopenEditorOverlay()
                            }
                            .buttonStyle(.plain)
                            .controlSize(.small)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var hotKeyTab: some View {
        section("全局快捷键") {
            settingsGroup {
                ForEach(Array(CaptureMode.allCases.enumerated()), id: \.element.id) { offset, mode in
                    if offset > 0 { rowDivider }
                    settingsRow(mode.title) {
                        Button(
                            controller.recordingHotKeyMode == mode
                                ? "按下快捷键…"
                                : controller.shortcut(for: mode)
                        ) {
                            controller.beginHotKeyRecording(mode)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .monospaced()
                        .disabled(controller.isBusy)
                    }
                }
            }
            footnote(
                controller.recordingHotKeyMode == nil
                    ? "点击右侧按钮后按下新组合键（需含 ⌘/⌥/⌃）。"
                    : "请按下新的快捷键，Esc 取消。"
            )
        }
    }

    @ViewBuilder
    private var aboutTab: some View {
        section("关于") {
            settingsGroup {
                VStack(spacing: 14) {
                    Image(nsImage: Self.appIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Self.appDisplayName)
                                .font(.system(size: 18, weight: .semibold))
                            Text(Self.appVersionLabel)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Text("菜单栏截图，原生像素无损输出")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Link(destination: Self.websiteURL) {
                            Label("访问官网", systemImage: "globe")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 28)
            }
        }

        section("软件更新") {
            settingsGroup {
                settingsRow("自动检查更新") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { enabled in
                                updater.setAutomaticallyChecksForUpdates(enabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(updater.configurationIssue != nil)
                }
                rowDivider
                settingsRow("自动下载更新") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { updater.automaticallyDownloadsUpdates },
                            set: { enabled in
                                updater.setAutomaticallyDownloadsUpdates(enabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(
                        updater.configurationIssue != nil
                            || !updater.automaticallyChecksForUpdates
                    )
                }
                rowDivider
                HStack {
                    if let issue = updater.configurationIssue {
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("通过已签名的自分发更新源获取新版本。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("检查更新…") {
                        updater.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!updater.canCheckForUpdates)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }

    // MARK: - Building blocks

    private static var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "YouShot"
    }

    private static let websiteURL = URL(string: "https://youshot.yayalu.top")!

    private static var appVersionLabel: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short)(\(build))"
    }

    private static var appIconImage: NSImage {
        if let icon = NSApp.applicationIconImage, icon.size.width > 0 {
            return icon
        }
        if let url = Bundle.main.url(forResource: "AppIcon-1024", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "YouShot")
            ?? NSImage(size: NSSize(width: 52, height: 52))
    }


    private var delayPresetBinding: Binding<Int> {
        Binding(
            get: {
                [0, 3, 5, 10].contains(controller.delaySeconds) ? controller.delaySeconds : -1
            },
            set: { controller.delaySeconds = $0 }
        )
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != tab.title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.86))
                    .padding(.horizontal, 5)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 5)
            .padding(.top, 2)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(groupBG)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private func settingsRow<Content: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func pillPicker<Value: Hashable>(
        selection: Binding<Value>,
        options: [(Value, String)],
        disabled: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, item in
                let selected = selection.wrappedValue == item.0
                Button {
                    selection.wrappedValue = item.0
                } label: {
                    Text(item.1)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func compactSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        percent: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            // `Slider(..., step:)` 在新 macOS 外观中会自动显示底部刻度。
            // 以 Binding 保持相同的离散步进，同时使用无刻度的连续 Slider。
            Slider(value: snappedBinding(value, range: range, step: step), in: range)
                .frame(width: 150)
            Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
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

/// macOS 26 及以上使用系统 Liquid Glass；旧系统保持原生毛玻璃材质。
private struct SidebarGlassBackground: View {
    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
                .overlay {
                    // 玻璃仍取样桌面，但用语义窗口色稳定激活/非激活状态下的对比度。
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(0.72)
                        .allowsHitTesting(false)
                }
        } else {
            FrostedSidebarBackground()
        }
    }
}

private struct FrostedSidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}
