import AppKit

/// Coordinates the overlay and the TIS switch in response to hotkey events.
///
/// State machine:
///   idle ── hotkeyDown ──▶ pendingTap
///     pendingTap ── (>200ms or extra Space) ──▶ holdActive (overlay shown)
///     pendingTap ── modifierRelease ──▶ quick switch to next source ──▶ idle
///     holdActive ── Space / Shift+Space ──▶ moves highlight
///     holdActive ── modifierRelease ──▶ commit highlighted source ──▶ idle
@MainActor
final class SwitcherController {
    /// How long the hotkey can be held before a tap becomes a hold.
    static let tapHoldThreshold: TimeInterval = 0.2

    private enum Mode { case idle, pendingTap, holdActive }

    private let overlay: OverlayPanel
    private var mode: Mode = .idle
    private var tapTimer: DispatchWorkItem?
    private var sources: [InputSource] = []
    private var selectedIndex = 0

    init(overlay: OverlayPanel) {
        self.overlay = overlay
    }

    // MARK: - Hotkey events

    func handleHotkeyDown() {
        loadSources()
        guard sources.count > 1 else {
            mode = .idle
            return
        }
        mode = .pendingTap

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .pendingTap else { return }
            self.transitionToHold()
        }
        tapTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tapHoldThreshold, execute: work)
    }

    func handleAdvance() {
        guard mode != .idle else { return }
        forceHoldMode()
        moveSelection(by: +1)
    }

    func handleRetreat() {
        guard mode != .idle else { return }
        forceHoldMode()
        moveSelection(by: -1)
    }

    func handleCommit() {
        cancelTapTimer()
        defer { mode = .idle }

        switch mode {
        case .pendingTap:
            // Released within threshold and only one Space press → jump back to
            // the most-recently-used source (Cmd+Tab style).
            InputSwitcher.selectMostRecentlyUsed()
        case .holdActive:
            if !sources.isEmpty {
                let chosen = sources[selectedIndex]
                if chosen.id != InputSources.currentKeyboardSource()?.id {
                    InputSources.select(chosen)
                }
            }
            overlay.dismiss()
        case .idle:
            break
        }
    }

    // MARK: - Internals

    private func loadSources() {
        sources = InputSources.selectableKeyboardSources()
        let currentID = InputSources.currentKeyboardSource()?.id
        let currentIndex = sources.firstIndex { $0.id == currentID } ?? 0
        // Pre-select the most-recently-used source so committing immediately
        // matches the quick-tap behavior. Fall back to the next source when no
        // history exists yet (first use after launch).
        if let previousID = InputSourceHistory.shared.previousID,
           let previousIndex = sources.firstIndex(where: { $0.id == previousID }),
           previousIndex != currentIndex {
            selectedIndex = previousIndex
        } else {
            selectedIndex = wrap(currentIndex + 1)
        }
    }

    private func transitionToHold() {
        mode = .holdActive
        guard sources.count > 1 else { return }
        overlay.present(sources: sources, selectedIndex: selectedIndex)
    }

    private func forceHoldMode() {
        guard mode == .pendingTap else { return }
        cancelTapTimer()
        transitionToHold()
    }

    private func moveSelection(by delta: Int) {
        guard !sources.isEmpty else { return }
        selectedIndex = wrap(selectedIndex + delta)
        overlay.setSelectedIndex(selectedIndex)
    }

    private func wrap(_ i: Int) -> Int {
        let count = sources.count
        guard count > 0 else { return 0 }
        return ((i % count) + count) % count
    }

    private func cancelTapTimer() {
        tapTimer?.cancel()
        tapTimer = nil
    }
}
