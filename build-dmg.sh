#!/bin/bash
set -euo pipefail

# Quick local DMG (ad-hoc signed, not notarized). For a release use scripts/release.sh.
# Named -dev so it can't be mistaken for, or overwrite, a release DMG.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Stowaway"
SCHEME="Stowaway"
DMG_NAME="Stowaway-dev.dmg"
BUILD_DIR="build"
STAGE_DIR="$BUILD_DIR/dmg-stage"
DMG_BUILDER="${DMG_BUILDER:-$HOME/Projects/dmg-builder/build-dmg.sh}"

echo "==> Regenerating Xcode project..."
xcodegen generate

echo "==> Building Release..."
xcodebuild -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/derived" \
    build | tail -5

APP_PATH="$BUILD_DIR/derived/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Build failed — $APP_PATH not found"
    exit 1
fi

if [ "$DMG_BUILDER" != "none" ] && [ -x "$DMG_BUILDER" ]; then
    if "$DMG_BUILDER" "$APP_NAME" "$APP_PATH" "$BUILD_DIR/$DMG_NAME"; then
        exit 0
    fi
    echo "==> $DMG_BUILDER failed; falling back to a plain DMG."
fi

echo "==> Staging DMG contents..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating DMG..."
rm -f "$BUILD_DIR/$DMG_NAME"
hdiutil create "$BUILD_DIR/$DMG_NAME" \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -format UDZO \
    -fs HFS+ \
    -ov

rm -rf "$STAGE_DIR"

echo "==> Done: $BUILD_DIR/$DMG_NAME"
ls -lh "$BUILD_DIR/$DMG_NAME"
