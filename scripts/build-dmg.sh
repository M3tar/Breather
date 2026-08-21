#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 0.2.0" >&2
  exit 1
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Version must look like 0.2.0, 0.2.0-beta.1, or 0.2.0-rc.1." >&2
  exit 1
fi

APP_NAME="Breather"
PROJECT="Breather.xcodeproj"
SCHEME="Breather"
CONFIGURATION="Release"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/ReleaseDerivedData"
ARCHIVES_DIR="$ROOT_DIR/build/Archives"
ARCHIVE_PATH="$ARCHIVES_DIR/$APP_NAME-$VERSION.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
INTERMEDIATE_APP_PATH="$BUILD_DIR/Build/Intermediates.noindex/ArchiveIntermediates/$SCHEME/InstallationBuildProductsLocation/Applications/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
MODULE_CACHE="$ROOT_DIR/build/ModuleCache"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
DMG_ROOT=""

cleanup() {
  local registered_app
  for registered_app in "$INTERMEDIATE_APP_PATH" "${DMG_ROOT:+$DMG_ROOT/$APP_NAME.app}"; do
    if [[ -n "$registered_app" ]]; then
      "$LSREGISTER" -u "$registered_app" >/dev/null 2>&1 || true
    fi
  done

  if [[ -n "$DMG_ROOT" && -d "$DMG_ROOT" ]]; then
    case "$DMG_ROOT" in
      "$DIST_DIR"/.dmg-root.*) rm -rf "$DMG_ROOT" ;;
      *) echo "Refusing to clean unexpected DMG staging path: $DMG_ROOT" >&2 ;;
    esac
  fi
}
trap cleanup EXIT

mkdir -p "$ARCHIVES_DIR" "$DIST_DIR"
case "$ARCHIVE_PATH" in
  "$ARCHIVES_DIR"/Breather-*.xcarchive) rm -rf "$ARCHIVE_PATH" ;;
  *) echo "Refusing to replace unexpected archive path: $ARCHIVE_PATH" >&2; exit 1 ;;
esac

echo "==> Archiving $APP_NAME $VERSION ($CONFIGURATION)"
xcodebuild \
  -project "$ROOT_DIR/$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$BUILD_DIR" \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  archive

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected archived app was not found at: $APP_PATH" >&2
  exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$VERSION" ]]; then
  echo "Archived app version $APP_VERSION does not match requested version $VERSION." >&2
  exit 1
fi

echo "==> Preparing DMG contents"
DMG_ROOT="$(mktemp -d "$DIST_DIR/.dmg-root.XXXXXX")"
ditto "$APP_PATH" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"

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
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo
echo "Done:"
echo "  $DMG_PATH"
echo
echo "Open it with:"
echo "  open \"$DMG_PATH\""
