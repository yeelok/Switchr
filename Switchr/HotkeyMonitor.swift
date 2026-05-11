import AppKit
import ApplicationServices

// Shift is consulted while the hotkey is "active" to invert the navigation
// direction; it isn't part of the binding (and the recorder rejects it).
private let kHotkeyInverseModifier: CGEventFlags = .maskShift

@MainActor
final class HotkeyMonitor {
    /// Called once when the hotkey first becomes active (mods + Space pressed).
    var onHotkeyDown: (() -> Void)?
    /// Called for each Space press while mods are still held (no Shift).
    var onAdvance: (() -> Void)?
    /// Called for each Shift+Space press while mods are still held.
    var onRetreat: (() -> Void)?
    /// Called when the user lifts a required modifier — commit + dismiss.
    var onCommit: (() -> Void)?

    /// True between hotkey-down and modifier-release.
    private(set) var isActive = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionPollTimer: Timer?

    /// Install the event tap. If Accessibility permission is missing, prompt
    /// the user and poll until it's granted.
    func start() {
        if installEventTap() { return }
        promptForAccessibility()
        startPermissionPolling()
    }

    // MARK: - Accessibility

    private func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                if self.installEventTap() {
                    timer.invalidate()
                    self.permissionPollTimer = nil
                }
            }
        }
    }

    private func promptForAccessibility() {
        let alert = NSAlert()
        let bindingDisplay = HotkeyStore.shared.binding.displayString
        alert.messageText = "Switchr needs Accessibility permission"
        alert.informativeText = """
            Switchr listens for the \(bindingDisplay) hotkey using a system event tap, \
            which requires Accessibility access.

            Open System Settings → Privacy & Security → Accessibility and toggle \
            Switchr on. The app will pick it up automatically — no relaunch needed.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        alert.alertStyle = .warning

        // Make the alert visible even though we're an .accessory app.
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        } else {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Event tap

    @discardableResult
    private func installEventTap() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return MainActor.assumeIsolated {
                monitor.handle(type: type, event: event)
            }
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.tap = port
        self.runLoopSource = source
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The kernel can disable our tap if we take too long; just turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let binding = HotkeyStore.shared.binding
        let flags = event.flags
        // Trigger requires an *exact* match of the bound modifier set
        // (ignoring Shift, which is reserved for reverse-nav), so e.g.
        // a Cmd+Space binding doesn't fire on Ctrl+Cmd+Space.
        let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        let modsExactMatch =
            flags.intersection(modifierMask) == binding.modifiers.intersection(modifierMask)
        // Commit uses the lenient "still held" check so pressing an extra
        // modifier mid-hold doesn't dismiss the overlay.
        let bindingModsHeld = flags.contains(binding.modifiers)

        switch type {
        case .keyDown:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

            if keyCode == binding.cgKeyCode && modsExactMatch {
                if !isAutoRepeat {
                    if isActive {
                        if flags.contains(kHotkeyInverseModifier) {
                            onRetreat?()
                        } else {
                            onAdvance?()
                        }
                    } else {
                        isActive = true
                        onHotkeyDown?()
                    }
                }
                return nil  // consume — don't let the system see Space
            }

        case .keyUp:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == binding.cgKeyCode && isActive {
                return nil  // also swallow the bound key's up event
            }

        case .flagsChanged:
            if isActive && !bindingModsHeld {
                isActive = false
                onCommit?()
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }
}
