#!/bin/sh
# Crée build/ValetDesktop-<version>.dmg (appli + raccourci vers /Applications) et son empreinte SHA-256.
# Usage : ./scripts/make-dmg.sh   (reconstruit toujours l'appli avant)
set -eu
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
APP="build/Valet Desktop.app"
DMG="build/ValetDesktop-${VERSION}.dmg"

./build.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Valet Desktop ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
codesign --force --sign - "$DMG"

(cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "OK : $DMG"
cat "$DMG.sha256"
