#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT_DIR/assets/app_icon.svg"
PNG_INPUT="$ROOT_DIR/assets/app_icon.png"
OUT="$ROOT_DIR/assets/AppIcon.icns"
TMP_DIR="$ROOT_DIR/assets/AppIcon.iconset"

if [[ ! -f "$SVG" && ! -f "$PNG_INPUT" ]]; then
  echo "Missing icon source. Provide $PNG_INPUT or $SVG"
  exit 1
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

PNG_1024="$TMP_DIR/icon_1024.png"
if [[ -f "$PNG_INPUT" ]]; then
  sips -z 1024 1024 "$PNG_INPUT" --out "$PNG_1024" >/dev/null
else
  if ! sips -s format png "$SVG" --out "$PNG_1024" >/dev/null 2>&1; then
    qlmanage -t -s 1024 -o "$TMP_DIR" "$SVG" >/dev/null 2>&1
    if [[ -f "$TMP_DIR/app_icon.svg.png" ]]; then
      mv "$TMP_DIR/app_icon.svg.png" "$PNG_1024"
    fi
  fi
fi

if [[ ! -f "$PNG_1024" ]]; then
  echo "Failed to render PNG from SVG."
  exit 1
fi

# Create the rest of the iconset sizes.
cp "$PNG_1024" "$TMP_DIR/icon_512x512@2x.png"
sips -z 512 512 "$PNG_1024" --out "$TMP_DIR/icon_512x512.png" >/dev/null
sips -z 512 512 "$PNG_1024" --out "$TMP_DIR/icon_256x256@2x.png" >/dev/null
sips -z 256 256 "$PNG_1024" --out "$TMP_DIR/icon_256x256.png" >/dev/null
sips -z 256 256 "$PNG_1024" --out "$TMP_DIR/icon_128x128@2x.png" >/dev/null
sips -z 128 128 "$PNG_1024" --out "$TMP_DIR/icon_128x128.png" >/dev/null
sips -z 64 64 "$PNG_1024" --out "$TMP_DIR/icon_32x32@2x.png" >/dev/null
sips -z 32 32 "$PNG_1024" --out "$TMP_DIR/icon_32x32.png" >/dev/null
sips -z 32 32 "$PNG_1024" --out "$TMP_DIR/icon_16x16@2x.png" >/dev/null
sips -z 16 16 "$PNG_1024" --out "$TMP_DIR/icon_16x16.png" >/dev/null

rm -f "$PNG_1024"

iconutil -c icns "$TMP_DIR" -o "$OUT"
rm -rf "$TMP_DIR"

echo "Built icon:"
echo "  $OUT"
