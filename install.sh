#!/bin/bash
# Installs the latest Life Wallpaper into ~/Applications and starts it.
#   curl -fsSL https://raw.githubusercontent.com/PSycH0buNnY01/life-wallpaper/main/install.sh | bash
set -euo pipefail

REPO="PSycH0buNnY01/life-wallpaper"
URL="https://github.com/$REPO/releases/latest/download/LifeWallpaper.zip"
DEST="$HOME/Applications"
APP="$DEST/Life Wallpaper.app"

[ "$(uname)" = "Darwin" ] || { echo "Life Wallpaper only runs on macOS."; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Life Wallpaper…"
curl -fsSL "$URL" -o "$TMP/LifeWallpaper.zip"
ditto -x -k "$TMP/LifeWallpaper.zip" "$TMP"

pkill -x LifeWallpaper 2>/dev/null && sleep 1 || true
mkdir -p "$DEST"
rm -rf "$APP"
mv "$TMP/Life Wallpaper.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

open "$APP"
echo "Installed to $APP — look for the grid icon in your menu bar."
