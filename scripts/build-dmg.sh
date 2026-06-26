#!/bin/bash
set -e

APP_NAME="ClaudeMonitor"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
SCHEME="ClaudeMonitor"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/build"
STAGE_DIR="${BUILD_DIR}/stage"
DMG_PATH="${PROJECT_DIR}/${DMG_NAME}"

echo "▶ Building Release..."
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}/derived" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  build | tail -3

APP_SRC="$(find "${BUILD_DIR}/derived" -name "${APP_NAME}.app" -maxdepth 6 | head -1)"

if [ -z "$APP_SRC" ]; then
  echo "✗ .app not found"
  exit 1
fi

echo "▶ Ad-hoc signing..."
codesign --deep --force --sign "-" "$APP_SRC"

echo "▶ Staging..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_SRC" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"

echo "▶ Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGE_DIR"

echo "✓ Done: ${DMG_PATH}"
