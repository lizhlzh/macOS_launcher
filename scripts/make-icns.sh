#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE_PNG="$ROOT_DIR/Resources/AppIcon.png"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
ICNS_PATH="$ROOT_DIR/Resources/AppIcon.icns"
SOURCE_TIFF="$ROOT_DIR/.build/AppIcon.tiff"

if [[ ! -f "$SOURCE_PNG" || "${LUMA_GENERATE_DEFAULT_ICON:-0}" == "1" ]]; then
  swift "$ROOT_DIR/scripts/generate-icon.swift" "$SOURCE_PNG"
fi

mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

if ! iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH" >/dev/null 2>&1; then
  sips -s format tiff "$SOURCE_PNG" --out "$SOURCE_TIFF" >/dev/null
  tiff2icns "$SOURCE_TIFF" "$ICNS_PATH"
fi

echo "$ICNS_PATH"
