#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
APP_NAME="Codex Usage Meter.app"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ENTITLEMENTS_PATH="$ROOT_DIR/CodexUsageMeter/CodexUsageMeter.entitlements"

sign_app() {
  local app_path="$1"
  local bundle_identifier

  bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")"

  /usr/bin/xattr -cr "$app_path"

  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    /usr/bin/codesign \
      --force \
      --deep \
      --sign - \
      --timestamp=none \
      --identifier "$bundle_identifier" \
      --entitlements "$ENTITLEMENTS_PATH" \
      "$app_path"
  else
    /usr/bin/codesign \
      --force \
      --deep \
      --options runtime \
      --sign "$SIGN_IDENTITY" \
      --timestamp \
      --entitlements "$ENTITLEMENTS_PATH" \
      "$app_path"
  fi

  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"

xcodegen generate --spec "$ROOT_DIR/project.yml"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project "$ROOT_DIR/CodexUsageMeter.xcodeproj" \
  -scheme CodexUsageMeter \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  build

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ZIP_PATH="$DIST_DIR/CodexUsageMeter-${VERSION}-macOS.zip"
DMG_PATH="$DIST_DIR/CodexUsageMeter-${VERSION}-macOS.dmg"

sign_app "$APP_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
/usr/bin/xattr -cr "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
/usr/bin/hdiutil create \
  -volname "Codex Usage Meter" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

echo "Created:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
