#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Luma"
BUNDLE_ID="com.lizhlzh.luma"
VERSION="1.0"
BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/release"
APP_BUILD_DIR="$REPO_ROOT/build"
APP_PATH="$APP_BUILD_DIR/$APP_NAME.app"

INSTALL_DIR="$HOME/Applications"
OPEN_AFTER_INSTALL=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)
      INSTALL_DIR="/Applications"
      shift
      ;;
    --no-open)
      OPEN_AFTER_INSTALL=false
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--system] [--no-open]"
      exit 1
      ;;
  esac
done

echo "==> Repo: $REPO_ROOT"
cd "$REPO_ROOT"

echo "==> Building release binary..."
swift build -c release --product "$APP_NAME"

BINARY_PATH="$BUILD_DIR/$APP_NAME"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Build succeeded but binary not found: $BINARY_PATH"
  exit 1
fi

echo "==> Creating app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$APP_NAME"

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>

    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>

    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>

    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>

    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>

    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>

    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
EOF

echo "APPL????" > "$APP_PATH/Contents/PkgInfo"

echo "==> Ad-hoc signing app..."
codesign --force --deep --sign - "$APP_PATH"

echo "==> Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "==> Quitting running $APP_NAME..."
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_PATH" "$INSTALL_DIR/$APP_NAME.app"

echo "==> Removing quarantine attribute if present..."
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME.app" >/dev/null 2>&1 || true

echo "==> Verifying signature..."
codesign --verify --deep --strict "$INSTALL_DIR/$APP_NAME.app"

echo "==> Installed: $INSTALL_DIR/$APP_NAME.app"

if [[ "$OPEN_AFTER_INSTALL" == "true" ]]; then
  echo "==> Opening $APP_NAME..."
  open "$INSTALL_DIR/$APP_NAME.app"
fi

echo "Done."