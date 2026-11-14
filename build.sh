#!/bin/bash
# Збирає Parallel.app у ./build. Використання: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Parallel"

APP="build/Parallel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Parallel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Готово: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/Parallel.app"
    cp -R "$APP" /Applications/
    echo "Встановлено в /Applications/Parallel.app"
fi
