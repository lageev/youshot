import AppKit
import SwiftUI

@main
struct YouShotApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appModel.controller)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("YouShot")
        }
    }
}

private enum MenuBarIcon {
    static let image: NSImage = {
        let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "YouShot")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

/// 设置用独立 AppKit 窗口，避免 SwiftUI `Window` 在激活时自动弹出。
@MainActor
final class SettingsPresenter {
    static let shared = SettingsPresenter()
    private var window: NSWindow?

    func show(controller: CaptureController) {
        if window == nil {
            let hosting = NSHostingController(rootView: ContentView().environmentObject(controller))
            let created = NSWindow(contentViewController: hosting)
            created.title = "YouShot 设置"
            created.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.backgroundColor = .clear
            created.isOpaque = false
            created.isMovableByWindowBackground = true
            created.isReleasedWhenClosed = false
            created.minSize = NSSize(width: 760, height: 560)
            created.setContentSize(NSSize(width: 840, height: 620))
            created.center()
            window = created
        }
        // 截图时窗口被置为透明并移出屏幕，这里恢复可见
        window?.alphaValue = 1
        window?.sharingType = .readWrite
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppModel: ObservableObject {
    let controller = CaptureController()
    private var hotKeys: HotKeyManager?

    init() {
        let manager = HotKeyManager(controller: controller)
        hotKeys = manager
        controller.onHotKeysChanged = { [weak manager, weak controller] in
            guard let manager, let controller else { return }
            manager.reload(
                current: controller.hotKeyCurrent,
                region: controller.hotKeyRegion,
                all: controller.hotKeyAll
            )
        }
        controller.onEscapeCancelEnabled = { [weak manager] enabled in
            manager?.setEscapeCancelEnabled(enabled)
        }
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var controller: CaptureController

    var body: some View {
        Button("截取当前屏幕（\(controller.shortcut(for: .currentDisplay))）") {
            controller.startCapture(mode: .currentDisplay)
        }
        .disabled(controller.isBusy)

        Button("区域选取（\(controller.shortcut(for: .region))）") {
            controller.startCapture(mode: .region)
        }
        .disabled(controller.isBusy)

        Button("截取所有屏幕（\(controller.shortcut(for: .allDisplays))）") {
            controller.startCapture(mode: .allDisplays)
        }
        .disabled(controller.isBusy)

        if controller.isBusy {
            Button("取消") {
                controller.cancel()
            }
        }

        if controller.hasEditor {
            Button("继续标注…") {
                controller.reopenEditorOverlay()
            }
        }

        Divider()

        Menu("延迟（\(controller.delaySeconds) 秒）") {
            ForEach([0, 3, 5, 10], id: \.self) { seconds in
                Button(seconds == 0 ? "立即" : "\(seconds) 秒") {
                    controller.delaySeconds = seconds
                }
            }
        }
        .disabled(controller.isBusy)

        Toggle("包含鼠标指针", isOn: $controller.includeCursor)
            .disabled(controller.isBusy)

        Toggle("窗口吸附", isOn: $controller.windowSnapEnabled)
            .disabled(controller.isBusy)

        Divider()

        Button("设置…") {
            SettingsPresenter.shared.show(controller: controller)
        }

        if let url = controller.lastFileURL {
            Button("显示最近截图") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }

        Divider()

        Button("退出 YouShot") {
            NSApp.terminate(nil)
        }
    }
}
