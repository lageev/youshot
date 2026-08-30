import AppKit
import Carbon
import Foundation

struct KeyChord: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let defaultCurrent = KeyChord(
        keyCode: UInt32(kVK_ANSI_3),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey)
    )
    static let defaultRegion = KeyChord(
        keyCode: UInt32(kVK_ANSI_4),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey)
    )
    static let defaultAll = KeyChord(
        keyCode: UInt32(kVK_ANSI_5),
        carbonModifiers: UInt32(cmdKey | shiftKey | optionKey)
    )

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyLabel(keyCode))
        return parts.joined()
    }

    var hasModifier: Bool {
        carbonModifiers & UInt32(cmdKey | optionKey | controlKey | shiftKey) != 0
    }

    static func from(event: NSEvent) -> KeyChord? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        // 忽略纯修饰键
        let code = UInt32(event.keyCode)
        if code == UInt32(kVK_Command) || code == UInt32(kVK_Shift)
            || code == UInt32(kVK_Option) || code == UInt32(kVK_Control)
            || code == UInt32(kVK_RightCommand) || code == UInt32(kVK_RightShift)
            || code == UInt32(kVK_RightOption) || code == UInt32(kVK_RightControl) {
            return nil
        }
        let chord = KeyChord(keyCode: code, carbonModifiers: carbon)
        // 全局热键至少需要一个非 Shift 修饰键，避免误触
        let strong = carbon & UInt32(cmdKey | optionKey | controlKey)
        guard strong != 0 else { return nil }
        return chord
    }

    private static func keyLabel(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_Space: return "Space"
        case kVK_Return: return "⏎"
        case kVK_Escape: return "Esc"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key\(keyCode)"
        }
    }
}

enum HotKeyDefaults {
    private static let currentKey = "hotkey.current"
    private static let regionKey = "hotkey.region"
    private static let allKey = "hotkey.all"

    static func loadCurrent() -> KeyChord { load(currentKey) ?? .defaultCurrent }
    static func loadRegion() -> KeyChord { load(regionKey) ?? .defaultRegion }
    static func loadAll() -> KeyChord { load(allKey) ?? .defaultAll }

    static func saveCurrent(_ chord: KeyChord) { save(chord, key: currentKey) }
    static func saveRegion(_ chord: KeyChord) { save(chord, key: regionKey) }
    static func saveAll(_ chord: KeyChord) { save(chord, key: allKey) }

    private static func load(_ key: String) -> KeyChord? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyChord.self, from: data)
    }

    private static func save(_ chord: KeyChord, key: String) {
        if let data = try? JSONEncoder().encode(chord) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
