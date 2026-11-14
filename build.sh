#!/bin/bash
# Збирає універсальний (Apple Silicon + Intel) Parallel.app у ./build.
# Використання: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=(arm64 x86_64)
BINS=()
for arch in "${ARCHS[@]}"; do
    triple="$arch-apple-macosx14.0"
    echo "▸ Збирання $arch"
    swift build -c release --triple "$triple"
    BINS+=("$(swift build -c release --triple "$triple" --show-bin-path)/Parallel")
done

APP="build/Parallel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/Parallel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
lipo -info "$APP/Contents/MacOS/Parallel"
echo "Готово: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/Parallel.app"
    cp -R "$APP" /Applications/
    echo "Встановлено в /Applications/Parallel.app"
fi
