#!/bin/bash
# Збирає універсальний Parallel.app і пакує його в build/Parallel-<версія>.dmg.
# Використання: ./scripts/make-dmg.sh [--skip-build]
set -euo pipefail
cd "$(dirname "$0")/.."

[[ "${1:-}" == "--skip-build" ]] || ./build.sh

APP="build/Parallel.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/Parallel-$VERSION.dmg"

STAGE="$(mktemp -d)/Parallel"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# Іконка тому.
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

rm -f "$DMG"
RW="$(dirname "$STAGE")/rw.dmg"
hdiutil create -volname "Parallel $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null

# Позначити том як такий, що має власну іконку (.VolumeIcon.icns).
MP=$(hdiutil attach -nobrowse -readwrite "$RW" | tail -1 | awk -F'\t' '{print $NF}')
SetFile -a C "$MP" 2>/dev/null || true
hdiutil detach "$MP" -quiet

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
codesign --force --sign - "$DMG"
rm -rf "$(dirname "$STAGE")"

echo "Готово: $PWD/$DMG ($(du -h "$DMG" | cut -f1))"
