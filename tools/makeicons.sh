#!/bin/zsh
# Собрать Resources/AppIcon.icns из docs/app-icon.png (1024×1024) и перерисовать картинку значков для README.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build

ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s docs/app-icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) docs/app-icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

swiftc tools/icongallery/main.swift Sources/BatteryIcon.swift Sources/HyperXLogo.swift -o build/icongallery
build/icongallery docs/menu-bar-icons.png
echo "Готово: Resources/AppIcon.icns, docs/menu-bar-icons.png"
