#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/tmp-clang-module-cache"
export SWIFTPM_CUSTOM_CACHE_PATH="$ROOT_DIR/.build/tmp-swiftpm-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_CUSTOM_CACHE_PATH"

"$ROOT_DIR/scripts/make-icns.sh" >/dev/null
swift build -c release 1>&2

APP_NAME="Luma"
BUNDLE_DIR="$ROOT_DIR/.build/release/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/Luma" "$MACOS_DIR/Luma"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null 2>&1 || true
fi

touch "$BUNDLE_DIR"

echo "$BUNDLE_DIR"
