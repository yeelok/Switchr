# Switchr

A macOS menu bar app that replaces the system input source switcher with a
custom popup styled like the legacy (pre-Sonoma) macOS overlay.

## Why

macOS Tahoe (26.x) has a bug where the system's input source switching
reverts unexpectedly when triggered by the standard shortcut. Switchr
listens for the hotkey itself with a `CGEventTap` and calls the Carbon
Text Input Sources (TIS) API directly to switch the source.

## Hotkey

Default: `Ctrl + Option + Space`. Reconfigurable from **Settings…**.

- **Tap** (press and release within ~200ms): jump to the most-recently-used
  input source. Tapping again jumps back — like ⌘Tab between apps. On the
  very first tap after launch (no history yet) it falls back to the next
  source in the list.
- **Hold**: a centered overlay appears listing every selectable keyboard
  source, with the most-recently-used one pre-highlighted. While holding:
  - `Space` advances the highlight (wraps around).
  - `Shift + Space` moves it the other way.
  - Release the modifiers to commit the highlighted source.

The history that drives "most-recently-used" is updated whenever the
active input source changes, regardless of how it was triggered (Switchr,
the system menu, globe key, another app). It is not persisted across
launches.

## Settings

Open from the menu bar icon → **Settings…**.

- **Switch input source** — record any shortcut. At least one of
  ⌃ ⌥ ⌘ is required. ⇧ is reserved as the reverse-navigation modifier
  while the hotkey is held, so it cannot be part of the binding itself.
- **Launch Switchr at login** — registers the app with `SMAppService`.
  After moving the app between locations (e.g. after running
  `tools/install.sh` for the first time), un-tick and re-tick this so the
  registration points at the new path.

## Accessibility permission

Switchr needs Accessibility permission to install the `CGEventTap` that
captures the hotkey. On first launch it prompts you and offers to open
the right pane. To grant manually:

1. **System Settings → Privacy & Security → Accessibility**
2. Toggle **Switchr** on (add it with `+` if it isn't listed).

No relaunch needed — the app polls and picks up the new permission
within ~1.5s.

If something gets stuck, removing Switchr from the list and granting
again usually fixes it.

## Build & run

From the project root, either open `Switchr.xcodeproj` in Xcode and ⌘R,
or build from the command line:

```sh
xcodebuild -project Switchr.xcodeproj -scheme Switchr -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Switchr-*/Build/Products/Debug/Switchr.app
```

## Install

To build a Release copy and install it into `/Applications` (replacing
any prior copy and relaunching):

```sh
tools/install.sh
```

After the first install from `/Applications`, re-grant Accessibility
permission and re-tick **Launch at login** as described above.

## Scope

Out of scope for now: per-app input source memory, animations beyond a
simple fade, persisted MRU history across launches.
