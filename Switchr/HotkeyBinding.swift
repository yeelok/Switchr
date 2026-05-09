import AppKit

/// A user-configurable keyboard shortcut.
///
/// The binding's modifiers must include at least one of Control / Option /
/// Command. Shift is reserved as the inverse-direction modifier while the
/// hotkey is held, so it cannot be part of the binding itself.
struct HotkeyBinding: Codable, Equatable {
    var modifiersRaw: UInt64
    var keyCode: UInt16
    var keyDisplay: String

    var modifiers: CGEventFlags { CGEventFlags(rawValue: modifiersRaw) }
    var cgKeyCode: CGKeyCode { CGKeyCode(keyCode) }

    var displayString: String {
        var s = ""
        if modifiers.contains(.maskControl)   { s += "⌃" }
        if modifiers.contains(.maskAlternate) { s += "⌥" }
        if modifiers.contains(.maskShift)     { s += "⇧" }
        if modifiers.contains(.maskCommand)   { s += "⌘" }
        if !s.isEmpty { s += " " }
        s += keyDisplay
        return s
    }

    static let `default` = HotkeyBinding(
        modifiersRaw: CGEventFlags([.maskControl, .maskAlternate]).rawValue,
        keyCode: 49,
        keyDisplay: "Space"
    )
}

extension Notification.Name {
    static let hotkeyBindingDidChange = Notification.Name("SwitchrHotkeyBindingDidChange")
}

@MainActor
final class HotkeyStore {
    static let shared = HotkeyStore()

    private let defaultsKey = "hotkeyBinding"
    private(set) var binding: HotkeyBinding {
        didSet {
            persist()
            NotificationCenter.default.post(name: .hotkeyBindingDidChange, object: nil)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            self.binding = saved
        } else {
            self.binding = .default
        }
    }

    func update(_ new: HotkeyBinding) {
        guard new != binding else { return }
        binding = new
    }

    func resetToDefault() { update(.default) }

    private func persist() {
        guard let data = try? JSONEncoder().encode(binding) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

/// Friendly name for keys whose `charactersIgnoringModifiers` doesn't read well.
enum KeyName {
    static func displayName(forKeyCode keyCode: UInt16, fallback: String) -> String {
        switch keyCode {
        case 36:  return "Return"
        case 48:  return "Tab"
        case 49:  return "Space"
        case 51:  return "Delete"
        case 53:  return "Escape"
        case 76:  return "Enter"
        case 117: return "Forward Delete"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "Page Up"
        case 121: return "Page Down"
        default:
            let cleaned = fallback.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Key \(keyCode)" : cleaned
        }
    }
}
