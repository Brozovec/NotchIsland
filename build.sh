#!/bin/zsh
# NotchIsland build
#   ./build.sh          sestaví build/NotchIsland.app
#   ./build.sh run      sestaví a spustí
#   ./build.sh install  sestaví a nakopíruje do /Applications (spustí odtud)
#   ./build.sh dmg      sestaví a vytvoří build/NotchIsland-<verze>.dmg
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "^.*\.swift:[0-9]+:[0-9]+: error:" && { echo "BUILD FAILED"; exit 1; } || true
[[ -x .build/release/NotchIsland ]] || { echo "BUILD FAILED"; exit 1; }
APP=build/NotchIsland.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchIsland "$APP/Contents/MacOS/NotchIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R Resources/Localizations/*.lproj "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Stabilní podpis = macOS si pamatuje oprávnění napříč buildy (ad hoc podpis se mění s každým buildem).
IDENTITY="${NOTCH_SIGN_IDENTITY:-Apple Development}"
codesign --force --deep --sign "$IDENTITY" "$APP" 2>/dev/null || { echo "Podpis '$IDENTITY' nenalezen, používám ad hoc"; codesign --force --deep --sign - "$APP"; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo "OK: $APP ($VERSION)"
case "$1" in
  run)
    pkill -x NotchIsland 2>/dev/null || true; sleep 0.3; open "$APP" ;;
  install)
    pkill -x NotchIsland 2>/dev/null || true; sleep 0.3
    rm -rf /Applications/NotchIsland.app && cp -R "$APP" /Applications/NotchIsland.app
    echo "Nainstalováno do /Applications"; open /Applications/NotchIsland.app ;;
  dmg)
    DMG="build/NotchIsland-$VERSION.dmg"; STAGE=build/dmg
    rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "NotchIsland" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"; echo "DMG: $DMG" ;;
esac
