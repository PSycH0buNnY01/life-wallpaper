#!/bin/bash
# Builds "Life Wallpaper.app" (universal: Apple Silicon + Intel) and a release zip.
# Needs the Xcode Command Line Tools: xcode-select --install
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo 0.0.0)}"
[ -n "$VERSION" ] || VERSION=0.0.0
NAME="Life Wallpaper"
EXE="LifeWallpaper"
BUILD="build"
APP="$BUILD/$NAME.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13.0" -o "$BUILD/$EXE-$arch" Sources/main.swift
done
lipo -create -output "$APP/Contents/MacOS/$EXE" "$BUILD/$EXE-arm64" "$BUILD/$EXE-x86_64"
rm "$BUILD/$EXE-arm64" "$BUILD/$EXE-x86_64"

swift scripts/make-icon.swift "$BUILD/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$BUILD/AppIcon.iconset"
rm -rf "$BUILD/AppIcon.iconset"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.psych0bunny01.LifeWallpaper</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: required on Apple Silicon, not a Developer ID.
codesign --force --deep --sign - "$APP"

(cd "$BUILD" && ditto -c -k --keepParent "$NAME.app" LifeWallpaper.zip)
echo "built $APP ($VERSION) and $BUILD/LifeWallpaper.zip"
