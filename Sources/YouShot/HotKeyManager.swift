import AppKit
import Carbon

final class HotKeyManager: @unchecked Sendable {
    private weak var controller: CaptureController?
    private var hotKeys: [EventHotKeyRef?] = []
    private var escapeHotKey: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(controller: CaptureController) {
        self.controller = controller
        installHandler()
        reload(
            current: HotKeyDefaults.loadCurrent(),
            region: HotKeyDefaults.loadRegion(),
            all: HotKeyDefaults.loadAll(),
            scroll: HotKeyDefaults.loadScroll()
        )
    }

    func reload(current: KeyChord, region: KeyChord, all: KeyChord, scroll: KeyChord) {
        let escapeOn = escapeHotKey != nil
        unregisterAll()
        register(current, id: 1)
        register(region, id: 2)
        register(all, id: 3)
        register(scroll, id: 4)
        if escapeOn {
            setEscapeCancelEnabled(true)
        }
    }

    /// 截图进行中临时占用 Esc，全局生效（不依赖窗口焦点）。
    func setEscapeCancelEnabled(_ enabled: Bool) {
        if let escapeHotKey {
            UnregisterEventHotKey(escapeHotKey)
            self.escapeHotKey = nil
        }
        guard enabled else { return }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5953_4845), id: 99) // 'YSHE'
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            escapeHotKey = hotKeyRef
        }
    }

    private func unregisterAll() {
        for ref in hotKeys {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeys.removeAll()
        if let escapeHotKey {
            UnregisterEventHotKey(escapeHotKey)
            self.escapeHotKey = nil
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                Task { @MainActor in
                    manager.handle(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
    }

    private func register(_ chord: KeyChord, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5953_4854), id: id) // 'YSHT'
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status == noErr {
            hotKeys.append(hotKeyRef)
        }
    }

    @MainActor
    private func handle(id: UInt32) {
        guard let controller else { return }
        if id == 99 {
            if controller.isBusy {
                controller.cancel()
            }
            return
        }
        guard !controller.isBusy else { return }
        switch id {
        case 1:
            controller.startCapture(mode: .currentDisplay)
        case 2:
            controller.startCapture(mode: .region)
        case 3:
            controller.startCapture(mode: .allDisplays)
        case 4:
            controller.startCapture(mode: .scroll)
        default:
            break
        }
    }
}
