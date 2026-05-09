# Switchr

A macOS menu bar app that replaces the system input source switcher with a
custom popup styled like the legacy (pre-Sonoma) macOS overlay.

## Why

macOS Tahoe (26.x) has a bug where the system's input source switching
reverts unexpectedly when triggered by the standard shortcut. Switchr
listens for the hotkey itself with a `CGEventTap` and calls the Carbon
Text Input Sources (TIS) API directly to switch the source.

## Hotkey

`Ctrl + Option + Space`

- **Tap** (press and release within ~200ms): switch to the next source.
- **Hold**: a centered overlay appears listing all selectable keyboard
  sources. Each `Space` advances the highlight (wrap-around);
  `Shift+Space` moves up. Release the modifiers to commit.

The hotkey is defined as a constant near the top of
`Switchr/HotkeyMonitor.swift` — change it there if you need to.

## Build & run

From the project root:

```sh
xcodebuild -project Switchr.xcodeproj -scheme Switchr -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Switchr-*/Build/Products/Debug/Switchr.app
```

Or open `Switchr.xcodeproj` in Xcode and ⌘R.

## Accessibility permission

Switchr needs Accessibility permission to install the `CGEventTap` that
captures the hotkey. On first launch it will prompt you and offer to open
the right pane. To grant it manually:

1. **System Settings → Privacy & Security → Accessibility**
2. Toggle **Switchr** on (add it with `+` if it isn't listed).
3. Re-launch Switchr.

If something gets stuck, removing Switchr from the list and granting again
usually fixes it.

## Finding input source IDs

Each TIS source has a stable bundle-style identifier, e.g.
`com.apple.keylayout.US` or `com.apple.inputmethod.SCIM.ITABC`. To list
the IDs of every selectable keyboard source on your system:

```sh
/usr/bin/python3 - <<'PY'
from Carbon import TIS  # not actually a thing — use the TIS C API instead
PY
```

…or, more practically, use a small Swift one-liner from a playground:

```swift
import Carbon
let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
for src in list {
    let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID)
    let namePtr = TISGetInputSourceProperty(src, kTISPropertyLocalizedName)
    let id = Unmanaged<CFString>.fromOpaque(idPtr!).takeUnretainedValue() as String
    let name = Unmanaged<CFString>.fromOpaque(namePtr!).takeUnretainedValue() as String
    print("\(id)\t\(name)")
}
```

## Scope

Out of scope for now: preferences UI, per-app input source memory,
launch-at-startup, animations beyond a simple fade. The hotkey is
hardcoded.
