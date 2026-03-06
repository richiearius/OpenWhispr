#!/bin/bash
set -euo pipefail

APP_NAME="OpenWhispr"
SCHEME="OpenWhispr"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_OUTPUT="$PROJECT_DIR/$APP_NAME.dmg"

echo "==> Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building Release..."
xcodebuild -project "$PROJECT_DIR/$SCHEME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination "platform=macOS" \
    build 2>&1 | tail -5

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$SCHEME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build failed — $APP_PATH not found"
    exit 1
fi

echo "==> Built: $APP_PATH"

# Rename .app if scheme name differs from app name
FINAL_APP="$BUILD_DIR/$APP_NAME.app"
cp -R "$APP_PATH" "$FINAL_APP"

echo "==> Creating DMG..."
mkdir -p "$DMG_STAGING"
cp -R "$FINAL_APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Remove old DMG if exists
rm -f "$DMG_OUTPUT"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$DMG_STAGING"

echo ""
echo "==> Done! DMG at: $DMG_OUTPUT"
echo "    Size: $(du -h "$DMG_OUTPUT" | cut -f1)"
