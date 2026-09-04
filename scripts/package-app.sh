#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Codex Touch Bar"
BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$ROOT_DIR/Packaging/Info.plist"
ICON_SOURCE="$ROOT_DIR/Packaging/AppIcon.png"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICON_FILE="$RESOURCES_DIR/AppIcon.icns"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION" --product CodexTouchBarApp
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/CodexTouchBarApp"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Missing built executable: $EXECUTABLE" >&2
    exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing app icon source: $ICON_SOURCE" >&2
    exit 1
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/CodexTouchBarApp"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null
codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null

echo "$BUNDLE_DIR"
