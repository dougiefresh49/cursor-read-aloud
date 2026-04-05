#!/usr/bin/env bash
#
# build_read_aloud_notifier_app.sh — Copy terminal-notifier.app, set bundle id/name,
# and replace the app icon with a PNG (for the *left* notification sender icon on macOS).
#
# Prerequisite: install terminal-notifier once, e.g.
#   brew install --cask terminal-notifier
#
# Usage:
#   bash scripts/build_read_aloud_notifier_app.sh
#   bash scripts/build_read_aloud_notifier_app.sh /path/to/terminal-notifier.app ~/Applications/Out.app icons/tmnt-icon.png
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE="${1:-/Applications/terminal-notifier.app}"
DEST="${2:-$HOME/Applications/CursorReadAloudNotifier.app}"
ICON_PNG="${3:-$PROJECT_DIR/icons/tmnt-icon.png}"

BUNDLE_ID="com.cursor.readaloud.notifier"
DISPLAY_NAME="Cursor Read Aloud"

warn() { echo "[build-notifier] $*" >&2; }
die() { warn "ERROR: $*"; exit 1; }

[ -d "$SOURCE" ] || die "Source app not found: $SOURCE (install: brew install --cask terminal-notifier)"
[ -f "$ICON_PNG" ] || die "Icon PNG not found: $ICON_PNG"
command -v sips >/dev/null || die "sips not found"
command -v iconutil >/dev/null || die "iconutil not found"
command -v codesign >/dev/null || die "codesign not found"

mkdir -p "$(dirname "$DEST")"
if [ -d "$DEST" ]; then
    warn "Removing existing $DEST"
    rm -rf "$DEST"
fi

warn "Copying $(basename "$SOURCE") → $(basename "$DEST")"
cp -R "$SOURCE" "$DEST"

PLIST="$DEST/Contents/Info.plist"
[ -f "$PLIST" ] || die "Missing Info.plist in bundle"

TMPICON="$(mktemp -d "${TMPDIR:-/tmp}/readaloud-icns.XXXXXX")"
ICONSET="$TMPICON/AppIcon.iconset"
mkdir -p "$ICONSET"

warn "Building AppIcon.icns from $ICON_PNG"
sips -z 16 16 "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
OUT_ICNS="$TMPICON/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"

RES="$DEST/Contents/Resources"
cp -f "$OUT_ICNS" "$RES/AppIcon.icns"
rm -rf "$TMPICON"

python3 - "$PLIST" "$BUNDLE_ID" "$DISPLAY_NAME" <<'PY'
import plistlib
import sys

path, bundle_id, name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "rb") as f:
    pl = plistlib.load(f)
pl["CFBundleIdentifier"] = bundle_id
pl["CFBundleName"] = name
pl["CFBundleDisplayName"] = name
pl["CFBundleIconFile"] = "AppIcon"
with open(path, "wb") as f:
    plistlib.dump(pl, f)
PY

warn "Ad-hoc signing bundle (required after icon/plist changes)"
codesign --force --deep -s - "$DEST" 2>/dev/null || codesign --force --deep --sign - "$DEST"

warn "Done."
echo ""
echo "  App:  $DEST"
echo "  Set in ~/.cursor/tts/config.json:"
echo "    \"terminal_notifier_app\": \"$DEST\""
echo ""
echo "  If macOS blocks the app the first time: right‑click → Open, or:"
echo "    xattr -cr \"$DEST\""
echo ""
