#!/usr/bin/env bash
#
# Build Switchr in Release config and install it to /Applications, replacing
# any prior copy. Re-run after every tweak.
#
# Usage:  tools/install.sh
#
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

TMP="${TMPDIR:-/tmp}"
DERIVED="${TMP%/}/switchr-build"
APP_NAME="Switchr.app"
BUILT_APP="$DERIVED/Build/Products/Release/$APP_NAME"
DEST="/Applications/$APP_NAME"

echo "▸ Building Release into $DERIVED…"
xcodebuild \
    -project Switchr.xcodeproj \
    -scheme Switchr \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -quiet \
    build

if [[ ! -d "$BUILT_APP" ]]; then
    echo "✗ Build did not produce $BUILT_APP" >&2
    exit 1
fi

if pgrep -x Switchr >/dev/null 2>&1; then
    echo "▸ Quitting running Switchr…"
    osascript -e 'tell application "Switchr" to quit' >/dev/null 2>&1 || true
    sleep 0.4
    pkill -x Switchr 2>/dev/null || true
fi

echo "▸ Installing to $DEST…"
rm -rf "$DEST"
ditto "$BUILT_APP" "$DEST"

echo "▸ Launching…"
open "$DEST"

cat <<EOF

✓ Installed at $DEST

If this is the first time the app is running from /Applications:
  • System Settings → Privacy & Security → Accessibility — remove any old
    Switchr entries and toggle the new one on. The app polls and picks it up
    within ~1.5s.
  • Settings… → Launch Switchr at login — re-tick so the registration points
    at /Applications/Switchr.app rather than a DerivedData path.
EOF
