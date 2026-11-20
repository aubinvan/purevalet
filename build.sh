#!/bin/sh
# Builds PureValet (universal arm64 + x86_64 binary) and assembles build/PureValet.app.
# Usage : ./build.sh
set -eu
cd "$(dirname "$0")"

VERSION="$(cat VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP="build/PureValet.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/PureValet"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PureValet"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
# App icon with light, dark and tinted variants (Icon Composer file → Assets.car). Needs Xcode's actool;
# the .icns above is the fallback (macOS 14–15, or builds with the Command Line Tools only).
ICON_NAME_KEY=""
if xcrun --find actool >/dev/null 2>&1 && xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
        --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist "$(mktemp)" --errors >/dev/null 2>&1 \
        && [ -f "$APP/Contents/Resources/Assets.car" ]; then
    ICON_NAME_KEY="<key>CFBundleIconName</key><string>AppIcon</string>"
else
    # Older Xcode (Icon Composer files need Xcode 26+) or Command Line Tools only.
    echo "Note: AppIcon.icon not compiled (needs Xcode 26+ actool): using AppIcon.icns, no dark/tinted variant."
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# Localizations: English (development language) and French.
for lang in en fr; do
    plutil -lint "Resources/$lang.lproj/Localizable.strings" >/dev/null
    mkdir -p "$APP/Contents/Resources/$lang.lproj"
    cp "Resources/$lang.lproj/Localizable.strings" "$APP/Contents/Resources/$lang.lproj/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PureValet</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>fr</string></array>
    <key>CFBundleDisplayName</key><string>PureValet</string>
    <key>CFBundleIdentifier</key><string>dev.aubin.purevalet</string>
    <key>CFBundleExecutable</key><string>PureValet</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    ${ICON_NAME_KEY}
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <!-- Health checks hit local Valet sites over plain HTTP: allow it for .test and local addresses only. -->
        <key>NSAllowsLocalNetworking</key><true/>
        <key>NSExceptionDomains</key>
        <dict>
            <key>test</key>
            <dict>
                <key>NSIncludesSubdomains</key><true/>
                <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
PLIST

# Ad-hoc signature (no Apple Developer account: the app is not notarized).
codesign --force --sign - "$APP"
echo "OK : $APP ($VERSION)"
