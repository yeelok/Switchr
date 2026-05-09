import AppKit
import Carbon

/// One selectable keyboard input source as exposed to the rest of the app.
struct InputSource: Identifiable, Equatable {
    let id: String
    let localizedName: String
    let icon: NSImage?
    fileprivate let tisRef: TISInputSource

    static func == (lhs: InputSource, rhs: InputSource) -> Bool { lhs.id == rhs.id }
}

enum InputSources {
    /// All currently-enabled, selectable keyboard sources, in TIS order.
    static func selectableKeyboardSources() -> [InputSource] {
        guard let listRef = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else {
            return []
        }
        let sources = listRef as! [TISInputSource]
        return sources.compactMap { ref -> InputSource? in
            guard isSelectableKeyboardSource(ref) else { return nil }
            return make(from: ref)
        }
    }

    /// The currently active keyboard input source, if any.
    static func currentKeyboardSource() -> InputSource? {
        guard let ref = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return make(from: ref)
    }

    /// Activate `source`. Returns true when TIS reports success.
    @discardableResult
    static func select(_ source: InputSource) -> Bool {
        TISSelectInputSource(source.tisRef) == noErr
    }

    // MARK: - Internals

    private static func isSelectableKeyboardSource(_ ref: TISInputSource) -> Bool {
        guard let category = stringProperty(ref, kTISPropertyInputSourceCategory),
              category == (kTISCategoryKeyboardInputSource as String) else {
            return false
        }
        guard let raw = TISGetInputSourceProperty(ref, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        let boolean = Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue()
        return CFBooleanGetValue(boolean)
    }

    private static func make(from ref: TISInputSource) -> InputSource? {
        guard let id = stringProperty(ref, kTISPropertyInputSourceID) else { return nil }
        let name = stringProperty(ref, kTISPropertyLocalizedName) ?? id
        return InputSource(id: id, localizedName: name, icon: loadIcon(ref), tisRef: ref)
    }

    private static func stringProperty(_ ref: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(ref, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func loadIcon(_ ref: TISInputSource) -> NSImage? {
        if let raw = TISGetInputSourceProperty(ref, kTISPropertyIconImageURL) {
            let url = Unmanaged<CFURL>.fromOpaque(raw).takeUnretainedValue() as URL
            if let img = NSImage(contentsOf: url) {
                return img
            }
        }
        if let raw = TISGetInputSourceProperty(ref, kTISPropertyIconRef) {
            let iconRef = OpaquePointer(raw)
            return NSImage(iconRef: iconRef)
        }
        return nil
    }
}
