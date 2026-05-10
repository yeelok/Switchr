import AppKit
import ApplicationServices

@MainActor
final class OverlayPanel {
    private static let width: CGFloat = 280
    private static let rowHeight: CGFloat = 60
    private static let outerPadding: CGFloat = 8
    private static let cornerRadius: CGFloat = 16

    private let panel: NSPanel
    private let background: OverlayBackgroundView
    private let listView: OverlayListView

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 0),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let background = OverlayBackgroundView(cornerRadius: Self.cornerRadius)

        let listView = OverlayListView()
        listView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(listView)
        NSLayoutConstraint.activate([
            listView.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.outerPadding),
            listView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.outerPadding),
            listView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.outerPadding),
            listView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.outerPadding),
        ])
        panel.contentView = background

        self.panel = panel
        self.background = background
        self.listView = listView
    }

    var isVisible: Bool { panel.isVisible }

    func present(sources: [InputSource], selectedIndex: Int) {
        listView.update(sources: sources, selectedIndex: selectedIndex)
        resizeToFit(rowCount: sources.count)
        positionOnFocusedScreen()

        let alreadyVisible = panel.isVisible
        if !alreadyVisible {
            panel.alphaValue = 0.0
        }
        panel.orderFrontRegardless()
        if !alreadyVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                panel.animator().alphaValue = 1.0
            }
        } else {
            panel.alphaValue = 1.0
        }
    }

    func setSelectedIndex(_ index: Int) {
        listView.setSelectedIndex(index)
    }

    func dismiss() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [panel] in
            panel.orderOut(nil)
        })
    }

    // MARK: - Layout

    private func resizeToFit(rowCount: Int) {
        let rows = max(rowCount, 1)
        let listHeight = CGFloat(rows) * Self.rowHeight + CGFloat(max(rows - 1, 0)) * OverlayListView.spacing
        let total = listHeight + Self.outerPadding * 2
        panel.setContentSize(NSSize(width: Self.width, height: total))
    }

    private func positionOnFocusedScreen() {
        let screen = focusedScreen()
        let frame = screen.visibleFrame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.midY - panelSize.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    /// Pick the screen that contains the focused window's center. Falls back
    /// to the screen under the cursor, then `NSScreen.main`.
    private func focusedScreen() -> NSScreen {
        if let center = focusedWindowCenterInAppKitCoords(),
           let s = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return s
        }
        let mouse = NSEvent.mouseLocation
        if let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return s
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func focusedWindowCenterInAppKitCoords() -> NSPoint? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let win = winRef else { return nil }
        let window = win as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }

        // AX coords use the primary screen's top-left as origin (y grows down).
        // AppKit screen frames use the primary screen's bottom-left (y grows up).
        let centerAX = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: centerAX.x, y: primaryHeight - centerAX.y)
    }
}

// MARK: - Background

/// Plain rounded fill, no border. Uses a hand-tuned gray that's visibly
/// distinct from a white desktop in light mode, with a dark-mode counterpart.
@MainActor
final class OverlayBackgroundView: NSView {
    private static let fillColor = NSColor(name: "SwitchrOverlayFill") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(white: 0.18, alpha: 1.0)
            : NSColor(white: 0.90, alpha: 1.0)
    }

    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        applyFillColor()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyFillColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyFillColor()
    }

    private func applyFillColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Self.fillColor.cgColor
        }
    }
}

// MARK: - List view

@MainActor
final class OverlayListView: NSView {
    static let spacing: CGFloat = 2

    private let stack = NSStackView()
    private var rows: [OverlayRowView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)

        stack.orientation = .vertical
        stack.spacing = Self.spacing
        stack.alignment = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(sources: [InputSource], selectedIndex: Int) {
        for row in rows { stack.removeArrangedSubview(row); row.removeFromSuperview() }
        rows = sources.map { OverlayRowView(source: $0) }
        for row in rows {
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setSelectedIndex(selectedIndex)
    }

    func setSelectedIndex(_ index: Int) {
        for (i, row) in rows.enumerated() {
            row.isSelected = (i == index)
        }
    }
}

// MARK: - Row

@MainActor
final class OverlayRowView: NSView {
    private static let textColor = NSColor(name: "SwitchrOverlayText") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(white: 0.75, alpha: 1.0)
            : NSColor(white: 0.25, alpha: 1.0)
    }

    private static let highlightColor = NSColor(name: "SwitchrOverlayHighlight") { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(white: 0.32, alpha: 1.0)
            : NSColor(white: 0.78, alpha: 1.0)
    }

    private let highlight = NSView()
    private let nameField = NSTextField(labelWithString: "")

    var isSelected: Bool = false {
        didSet { applySelection() }
    }

    init(source: InputSource) {
        super.init(frame: .zero)
        wantsLayer = true

        highlight.wantsLayer = true
        highlight.layer?.cornerRadius = 12
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        nameField.stringValue = source.localizedName
        nameField.font = .systemFont(ofSize: 18, weight: .regular)
        nameField.alignment = .center
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 60),

            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applySelection()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applySelection()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySelection()
    }

    private func applySelection() {
        let bg: NSColor = isSelected ? Self.highlightColor : .clear
        effectiveAppearance.performAsCurrentDrawingAppearance {
            highlight.layer?.backgroundColor = bg.cgColor
        }
        nameField.textColor = Self.textColor
    }
}
