#!/usr/bin/env bash
# Build a styled read-only DMG with background image and icon layout.
set -euo pipefail

APP_PATH="${1:?Usage: build-dmg.sh /path/to/HushPort.app [output.dmg]}"
APP_NAME="$(basename "$APP_PATH")"
DMG_PATH="${2:-$(dirname "$APP_PATH")/HushPort.dmg}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKGROUND="$SCRIPT_DIR/dmg-background.png"
VOLUME_NAME="HushPort"
STAGING="$(mktemp -d)"

if ! command -v create-dmg &>/dev/null; then
  echo "create-dmg is required. Install with: brew install create-dmg" >&2
  exit 1
fi

if [[ ! -f "$BACKGROUND" ]]; then
  echo "Missing background image: $BACKGROUND" >&2
  exit 1
fi

cleanup() {
  rm -rf "$STAGING"
  # Eject any leftover mounts from failed runs (ignore errors).
  while mount | grep -q "/Volumes/$VOLUME_NAME"; do
    hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet 2>/dev/null || break
  done
}
trap cleanup EXIT

# Unmount stale HushPort volumes so create-dmg can reuse the volname.
for mount_point in /Volumes/"$VOLUME_NAME"*; do
  [[ -d "$mount_point" ]] || continue
  hdiutil detach "$mount_point" -force -quiet 2>/dev/null || true
done

rm -f "$DMG_PATH"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/$APP_NAME"

# Window/icon layout tuned for Scripts/dmg-background.png (512×341).
# create-dmg example ratio (800×400 → 512×341) plus offset for circle artwork.
# Positions are icon top-left; 64px icons.
# APP_ICON_X=134
# APP_ICON_Y=178
# APPS_ICON_X=386
# APPS_ICON_Y=178
APP_ICON_X=118
APP_ICON_Y=158
APPS_ICON_X=396
APPS_ICON_Y=158

create-dmg \
  --volname "$VOLUME_NAME" \
  --background "$BACKGROUND" \
  --window-size 512 341 \
  --text-size 12 \
  --icon-size 64 \
  --icon "$APP_NAME" $APP_ICON_X $APP_ICON_Y \
  --hide-extension "$APP_NAME" \
  --app-drop-link $APPS_ICON_X $APPS_ICON_Y \
  --no-internet-enable \
  --format UDZO \
  "$DMG_PATH" \
  "$STAGING"

echo "$DMG_PATH"
