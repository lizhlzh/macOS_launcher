#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${1:-/Applications}"

APP_PATH="$("$ROOT_DIR/scripts/build-app.sh")"
DEST_PATH="$INSTALL_DIR/Luma.app"
EXPECTED_BUNDLE_ID="com.local.Luma"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

osascript -e 'tell application id "com.local.Luma" to quit' >/dev/null 2>&1 || true
sleep 0.4

bundle_id_at_path() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true
}

archive_registered_copy() {
  local app_path="$1"
  [[ -d "$app_path" ]] || return 0

  local bundle_id
  bundle_id="$(bundle_id_at_path "$app_path")"
  if [[ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
    echo "Refusing to archive unexpected app at $app_path" >&2
    return 1
  fi

  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$app_path" >/dev/null 2>&1 || true
  fi

  local parent_dir
  parent_dir="$(dirname "$app_path")"
  local backup_path="$parent_dir/.Luma-duplicate-$(date +%Y%m%d%H%M%S)"
  mv "$app_path" "$backup_path"
}

for existing_path in "/Applications/Luma.app" "$HOME/Applications/Luma.app"; do
  if [[ "$existing_path" != "$DEST_PATH" ]]; then
    archive_registered_copy "$existing_path"
  fi
done

mkdir -p "$INSTALL_DIR"
ditto "$APP_PATH" "$DEST_PATH"
touch "$DEST_PATH" "$DEST_PATH/Contents/Info.plist" "$DEST_PATH/Contents/Resources/AppIcon.icns"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_PATH" >/dev/null 2>&1 || true
fi

killall Dock >/dev/null 2>&1 || true
open "$DEST_PATH"

echo "$DEST_PATH"
