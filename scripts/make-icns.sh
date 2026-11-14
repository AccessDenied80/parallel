#!/bin/bash
# Перемальовує іконку і збирає Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/make-icon.swift Resources/icon-1024.png
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d Resources/icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Готово: Resources/AppIcon.icns"
