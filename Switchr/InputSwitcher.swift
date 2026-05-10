import Foundation

/// Coordinates the "switch to next source" / "switch to specific source" actions
/// that both the hotkey tap-flow and the menu use.
enum InputSwitcher {
    /// Advance to the next selectable keyboard source, wrapping around.
    /// No-op when zero or one source is enabled.
    @discardableResult
    static func advanceToNext() -> InputSource? { step(by: +1) }

    @discardableResult
    static func retreatToPrevious() -> InputSource? { step(by: -1) }

    /// Switch to the most-recently-used source if we have one recorded and it
    /// is still selectable; otherwise fall back to advancing to the next.
    @MainActor
    @discardableResult
    static func selectMostRecentlyUsed() -> InputSource? {
        let sources = InputSources.selectableKeyboardSources()
        guard sources.count > 1 else { return nil }

        let currentID = InputSources.currentKeyboardSource()?.id
        if let previousID = InputSourceHistory.shared.previousID,
           previousID != currentID,
           let target = sources.first(where: { $0.id == previousID }) {
            InputSources.select(target)
            return target
        }

        return advanceToNext()
    }

    private static func step(by delta: Int) -> InputSource? {
        let sources = InputSources.selectableKeyboardSources()
        guard sources.count > 1 else { return nil }

        let currentID = InputSources.currentKeyboardSource()?.id
        let currentIndex = sources.firstIndex { $0.id == currentID } ?? 0
        let count = sources.count
        let nextIndex = ((currentIndex + delta) % count + count) % count
        let next = sources[nextIndex]

        InputSources.select(next)
        return next
    }
}
