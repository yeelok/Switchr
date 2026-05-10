import AppKit
import ServiceManagement

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let recorder = ShortcutRecorderView()
    private let bindingLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Switchr Settings"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.delegate = self
        buildContent()
        refreshBindingLabel()
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        refreshLaunchAtLoginState()
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "Switch input source")
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.binding = HotkeyStore.shared.binding
        recorder.onCapture = { [weak self] new in
            HotkeyStore.shared.update(new)
            self?.refreshBindingLabel()
        }

        bindingLabel.font = .systemFont(ofSize: 11)
        bindingLabel.textColor = .secondaryLabelColor

        let hint = NSTextField(wrappingLabelWithString:
            "At least one of ⌃ ⌥ ⌘ is required. Shift is reserved as the reverse-navigation modifier while the hotkey is held.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let resetButton = NSButton(title: "Reset to Default", target: self, action: #selector(resetToDefault))
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        launchAtLoginCheckbox.title = "Launch Switchr at login"
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        refreshLaunchAtLoginState()

        let stack = NSStackView(views: [title, recorder, bindingLabel, hint, resetButton, separator, launchAtLoginCheckbox])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),

            recorder.heightAnchor.constraint(equalToConstant: 30),
            recorder.widthAnchor.constraint(equalToConstant: 200),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func refreshBindingLabel() {
        let b = HotkeyStore.shared.binding
        bindingLabel.stringValue = "Currently bound to \(b.displayString)."
        recorder.binding = b
    }

    @objc private func resetToDefault() {
        HotkeyStore.shared.resetToDefault()
        refreshBindingLabel()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = sender.state == .on
                ? "Couldn't enable launch at login"
                : "Couldn't disable launch at login"
            alert.informativeText = """
                \(error.localizedDescription)

                You can manage this manually in System Settings → General → Login Items.
                """
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Login Items")
            if alert.runModal() == .alertSecondButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    func windowWillClose(_ notification: Notification) {
        // Make sure the recorder isn't left in capture mode after the window closes.
        window?.makeFirstResponder(nil)
    }
}

// MARK: - Recorder

@MainActor
final class ShortcutRecorderView: NSView {
    var onCapture: ((HotkeyBinding) -> Void)?

    var binding: HotkeyBinding? {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { bounds.fill() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { isRecording = true }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        // Escape cancels recording without changing the binding.
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }

        let allowed: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        let pressed = event.modifierFlags.intersection(.deviceIndependentFlagsMask).intersection(allowed)
        let nonShift: NSEvent.ModifierFlags = [.control, .option, .command]

        // Need at least one of ⌃ ⌥ ⌘ — shift alone isn't enough.
        guard !pressed.intersection(nonShift).isEmpty else {
            NSSound.beep(); return
        }
        // Shift is reserved for reverse navigation while the hotkey is held.
        guard !pressed.contains(.shift) else {
            NSSound.beep(); return
        }

        let cgFlags = CGEventFlags(rawValue: UInt64(pressed.rawValue))
        let display = KeyName.displayName(
            forKeyCode: event.keyCode,
            fallback: event.charactersIgnoringModifiers ?? ""
        )
        let new = HotkeyBinding(
            modifiersRaw: cgFlags.rawValue,
            keyCode: event.keyCode,
            keyDisplay: display
        )
        binding = new
        window?.makeFirstResponder(nil)
        onCapture?(new)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if isRecording {
            text = "Press a shortcut…"
        } else {
            text = binding?.displayString ?? "Click to record"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let size = attr.size()
        attr.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: (bounds.height - size.height) / 2))
    }
}
