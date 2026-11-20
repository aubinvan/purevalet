#!/bin/sh
# Creates build/PureValet-<version>.dmg (app + /Applications shortcut) and its SHA-256.
# Usage: ./scripts/make-dmg.sh   (always rebuilds the app first)
set -eu
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
APP="build/PureValet.app"
DMG="build/PureValet-${VERSION}.dmg"

./build.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "PureValet ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
codesign --force --sign - "$DMG"

(cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "OK : $DMG"
cat "$DMG.sha256"
