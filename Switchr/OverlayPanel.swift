import AppKit
import ApplicationServices

@MainActor
final class OverlayPanel {
    private static let width: CGFloat = 280
    private static let rowHeight: CGFloat = 32
    private static let outerPadding: CGFloat = 8
    private static let cornerRadius: CGFloat = 12

    private let panel: NSPanel
    private let visualEffect: NSVisualEffectView
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
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let visualEffect = NSVisualEffectView(frame: panel.contentLayoutRect)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        // `maskImage` is the reliable way to round NSVisualEffectView corners —
        // setting `layer.cornerRadius` alone leaves the private blur subview
        // unclipped, which paints opaque squares in the corners.
        visualEffect.maskImage = Self.roundedMaskImage(cornerRadius: Self.cornerRadius)

        let listView = OverlayListView()
        listView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(listView)
        NSLayoutConstraint.activate([
            listView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: Self.outerPadding),
            listView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -Self.outerPadding),
            listView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: Self.outerPadding),
            listView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -Self.outerPadding),
        ])
        panel.contentView = visualEffect

        self.panel = panel
        self.visualEffect = visualEffect
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

    /// Builds a stretchable 9-slice rounded rect for `NSVisualEffectView.maskImage`.
    private static func roundedMaskImage(cornerRadius radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let size = NSSize(width: edge, height: edge)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

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
    private let highlight = NSView()
    private let nameField = NSTextField(labelWithString: "")
    private let iconView = NSImageView()

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
        nameField.font = .systemFont(ofSize: 18)
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameField)

        iconView.image = source.icon
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 60),

            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: iconView.leadingAnchor, constant: -16),

            iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 36),
        ])

        applySelection()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func applySelection() {
        if isSelected {
            highlight.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            nameField.textColor = .white
        } else {
            highlight.layer?.backgroundColor = NSColor.clear.cgColor
            nameField.textColor = .labelColor
        }
    }
}
