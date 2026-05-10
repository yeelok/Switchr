import Foundation
import Carbon

/// Tracks the most-recently-used keyboard input source so the hotkey can
/// "ping-pong" between the current and previous source (Cmd+Tab style)
/// rather than blindly advancing through the list.
///
/// Observes the system's TIS change notification so external switches
/// (system menu, globe key, other apps) update the history too.
@MainActor
final class InputSourceHistory {
    static let shared = InputSourceHistory()

    private(set) var currentID: String?
    private(set) var previousID: String?

    private init() {
        currentID = InputSources.currentKeyboardSource()?.id
    }

    func startObserving() {
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let newID = InputSources.currentKeyboardSource()?.id
        guard let newID, newID != currentID else { return }
        previousID = currentID
        currentID = newID
    }
}
