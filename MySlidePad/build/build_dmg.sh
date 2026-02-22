#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR"
SCHEME="MacSlide"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
APP_NAME="$SCHEME.app"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$SCHEME.dmg"

echo "==> Archiving $SCHEME..."
xcodebuild archive \
  -project "$PROJECT_DIR/$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  ONLY_ACTIVE_ARCH=NO \
  | tail -5

echo "==> Preparing DMG contents..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$DMG_DIR/"

echo "==> Creating styled DMG..."
rm -f "$DMG_PATH"

create-dmg \
  --volname "$SCHEME" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 160 \
  --text-size 14 \
  --icon "$APP_NAME" 165 175 \
  --app-drop-link 495 175 \
  --hide-extension "$APP_NAME" \
  --no-internet-enable \
  "$DMG_PATH" \
  "$DMG_DIR"

echo "==> Cleaning up..."
rm -rf "$DMG_DIR"

echo ""
echo "Done! DMG saved to: $DMG_PATH"
