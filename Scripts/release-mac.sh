#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0-beta.1}"
ARCHIVE_PATH="$ROOT/build/HushPortMac.xcarchive"
EXPORT_PATH="$ROOT/build/export-$VERSION"
DMG_PATH="$ROOT/build/HushPort-$VERSION.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-hushport-notary}"

cd "$ROOT"

echo "==> Archiving HushPortMacApp (Release)…"
xcodebuild \
  -project HushPort.xcodeproj \
  -scheme HushPortMacApp \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM=V2HN22942W \
  archive

echo "==> Exporting Developer ID signed app…"
rm -rf "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$ROOT/Scripts/ExportOptions-macOS.plist"

APP_PATH="$EXPORT_PATH/HushPort.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app at $APP_PATH" >&2
  exit 1
fi

echo "==> Notarizing app (requires notary profile: $NOTARY_PROFILE)…"
ZIP_PATH="$EXPORT_PATH/HushPort.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
  echo ""
  echo "Set up notary credentials once:"
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE \\"
  echo "    --apple-id YOUR_APPLE_ID_EMAIL \\"
  echo "    --team-id V2HN22942W"
  echo ""
  exit 1
fi

xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Building DMG…"
if ! command -v create-dmg &>/dev/null; then
  echo "Install create-dmg first: brew install create-dmg" >&2
  exit 1
fi
chmod +x "$ROOT/Scripts/build-dmg.sh"
"$ROOT/Scripts/build-dmg.sh" "$APP_PATH" "$DMG_PATH"

echo "==> Notarizing DMG…"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo ""
echo "Done."
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
echo ""
echo "Upload $DMG_PATH to GitHub Releases as v$VERSION"
