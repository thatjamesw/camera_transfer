#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Camera Media Importer"
APP_VERSION="2.0.0"
LEGACY_APP_NAME="Camera Media Transfer Wizard"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
ICON_PATH="$ROOT_DIR/assets/AppIcon.icns"
ICON_NAME="AppIcon"

cd "$ROOT_DIR"

if [[ -x "$ROOT_DIR/scripts/build_icon.sh" ]]; then
  "$ROOT_DIR/scripts/build_icon.sh" >/dev/null 2>&1 || true
fi

swift build -c release

rm -rf "$APP_DIR"
rm -rf "$ROOT_DIR/dist/${LEGACY_APP_NAME}.app"
rm -f "$ROOT_DIR/dist/${LEGACY_APP_NAME}.zip"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.jameswright.camerafilesort</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleExecutable</key>
  <string>CameraFileSortSwift</string>
  <key>CFBundleIconFile</key>
  <string>${ICON_NAME}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

cp "$BUILD_DIR/CameraFileSortSwift" "$APP_DIR/Contents/MacOS/CameraFileSortSwift"
if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$APP_DIR/Contents/Resources/${ICON_NAME}.icns"
fi

# Local builds use ad-hoc signing. Set CAMERA_SIGN_IDENTITY for Developer ID distribution.
SIGN_IDENTITY="${CAMERA_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --options runtime "$APP_DIR"
else
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP_DIR"
fi
codesign --verify --strict "$APP_DIR"

echo "Built app bundle:"
echo "  $APP_DIR"

ZIP_PATH="$ROOT_DIR/dist/${APP_NAME}.zip"
rm -f "$ZIP_PATH"
cd "$ROOT_DIR/dist"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "Built zip:"
echo "  $ZIP_PATH"
