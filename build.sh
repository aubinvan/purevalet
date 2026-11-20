#!/bin/sh
# Compile Valet Desktop (binaire universel arm64 + x86_64) et assemble build/Valet Desktop.app.
# Usage : ./build.sh
set -eu
cd "$(dirname "$0")"

VERSION="$(cat VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/Valet Desktop.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ValetDesktop"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ValetDesktop"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Valet Desktop</string>
    <key>CFBundleDisplayName</key><string>Valet Desktop</string>
    <key>CFBundleIdentifier</key><string>dev.aubin.valet-desktop</string>
    <key>CFBundleExecutable</key><string>ValetDesktop</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

# Signature ad hoc (pas de compte Apple Developer : l'appli n'est pas notarisée).
codesign --force --sign - "$APP"
echo "OK : $APP ($VERSION)"
