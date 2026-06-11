#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${1:-$HOME/Applications}"

APP_PATH="$("$ROOT_DIR/scripts/build-app.sh")"
DEST_PATH="$INSTALL_DIR/Luma.app"

osascript -e 'tell application id "com.local.Luma" to quit' >/dev/null 2>&1 || true
sleep 0.4

mkdir -p "$INSTALL_DIR"
ditto "$APP_PATH" "$DEST_PATH"
touch "$DEST_PATH" "$DEST_PATH/Contents/Info.plist" "$DEST_PATH/Contents/Resources/AppIcon.icns"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_PATH" >/dev/null 2>&1 || true
fi

open "$DEST_PATH"

echo "$DEST_PATH"
