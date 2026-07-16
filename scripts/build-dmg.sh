#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.1.0"
  exit 1
fi

VERSION="$1"
APP_NAME="Breather"
PROJECT="Breather.xcodeproj"
SCHEME="Breather"
CONFIGURATION="Release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/DerivedData"
PRODUCTS_DIR="$BUILD_DIR/Build/Products/$CONFIGURATION"
APP_PATH="$PRODUCTS_DIR/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
MODULE_CACHE="$ROOT_DIR/build/ModuleCache"

echo "==> Building $APP_NAME $VERSION ($CONFIGURATION)"
xcodebuild \
  -project "$ROOT_DIR/$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD_DIR" \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app was not found at: $APP_PATH"
  exit 1
fi

echo "==> Preparing DMG contents"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "==> Creating $DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Verifying DMG container"
hdiutil verify "$DMG_PATH"

echo "==> Verifying app bundle"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true

echo
echo "Done:"
echo "  $DMG_PATH"
echo
echo "Open it with:"
echo "  open \"$DMG_PATH\""
