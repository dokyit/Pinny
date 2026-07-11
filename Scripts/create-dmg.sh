#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Pinny/Info.plist")"
BUILD_ROOT="$ROOT/build/ReleaseDMG"
STAGING="$BUILD_ROOT/Pinny"
DIST="$ROOT/dist"
DMG="$DIST/Pinny-$VERSION-arm64.dmg"
MOUNT_POINT="$BUILD_ROOT/Mount"

rm -rf "$BUILD_ROOT"
mkdir -p "$STAGING" "$DIST" "$MOUNT_POINT"
rm -f "$DMG" "$DMG.sha256"

PINNY_RELEASE=1 "$ROOT/Scripts/build-local.sh"

/usr/bin/ditto "$ROOT/build/Local/Pinny.app" "$STAGING/Pinny.app"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/Documentation/INSTALL.txt" "$STAGING/Install Pinny.txt"

hdiutil create \
  -volname "Pinny $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"

hdiutil verify "$DMG"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT_POINT" >/dev/null
trap 'hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true' EXIT

codesign --verify --deep --strict --verbose=2 "$MOUNT_POINT/Pinny.app"
plutil -lint "$MOUNT_POINT/Pinny.app/Contents/Info.plist"
file "$MOUNT_POINT/Pinny.app/Contents/MacOS/Pinny" | grep -q 'arm64'

hdiutil detach "$MOUNT_POINT" >/dev/null
trap - EXIT

(cd "$DIST" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")

echo "Created $DMG"
echo "Checksum: $DMG.sha256"
