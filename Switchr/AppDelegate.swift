import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotkey = HotkeyMonitor()
    private let overlay = OverlayPanel()
    private lazy var controller = SwitcherController(overlay: overlay)
    private var prefsController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuBarItem()
        wireHotkey()
        hotkey.start()
    }

    private func installMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Pick any SF Symbol you like — e.g. "keyboard", "globe", "character.bubble",
            // "command", "globe.asia.australia". Browse with the SF Symbols app.
            let icon = NSImage(systemSymbolName: "keyboard",
                               accessibilityDescription: "Switchr")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Now", action: #selector(toggleNow), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Switchr", action: #selector(quit), keyEquivalent: "q")
            .target = self
        item.menu = menu

        self.statusItem = item
    }

    private func wireHotkey() {
        let controller = self.controller
        hotkey.onHotkeyDown = { controller.handleHotkeyDown() }
        hotkey.onAdvance    = { controller.handleAdvance() }
        hotkey.onRetreat    = { controller.handleRetreat() }
        hotkey.onCommit     = { controller.handleCommit() }
    }

    @objc private func toggleNow() {
        InputSwitcher.advanceToNext()
    }

    @objc private func openSettings() {
        if prefsController == nil {
            prefsController = PreferencesWindowController()
        }
        prefsController?.showWindow()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
