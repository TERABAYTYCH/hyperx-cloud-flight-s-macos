#!/bin/zsh
# Сборка HyperX Battery.app (universal: arm64 + x86_64), без Xcode-проекта и зависимостей.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/HyperX Battery.app"
BIN_NAME="HyperXBattery"
MIN_MACOS="13.0"
BUNDLE_ID="io.github.terabaytych.hyperx-battery"
# Версия: из git-тега (v1.2.0 → 1.2.0), иначе 1.0.0. Можно задать явно: VERSION=1.2.3 ./build.sh
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj
cp -R Resources/AppIcon.icns Resources/*.lproj "$APP/Contents/Resources/"

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos$MIN_MACOS" \
    -o "build/obj/$BIN_NAME-$arch" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/$BIN_NAME" build/obj/$BIN_NAME-*

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
  <key>CFBundleName</key><string>HyperX Battery</string>
  <key>CFBundleDisplayName</key><string>HyperX Battery</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$BIN_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 TERABAYTYCH. MIT License.</string>
</dict>
</plist>
PLIST

# Ad-hoc подпись: без неё Apple Silicon не запустит бинарник, а SMAppService не даст включить автозапуск.
codesign --force --sign - "$APP"
rm -rf build/obj
echo "Готово: $PWD/$APP"
