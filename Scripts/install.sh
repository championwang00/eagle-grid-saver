#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SAVER_PATH="$("$PROJECT_DIR/Scripts/build.sh")"
APP_PATH="$PROJECT_DIR/dist/Eagle Grid Saver.app"
INSTALL_DIR="$HOME/Library/Screen Savers"
APP_INSTALL_DIR="$HOME/Applications"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/EagleGridSaver.saver"
cp -R "$SAVER_PATH" "$INSTALL_DIR/EagleGridSaver.saver"

mkdir -p "$APP_INSTALL_DIR"
rm -rf "$APP_INSTALL_DIR/Eagle Grid Saver.app"
cp -R "$APP_PATH" "$APP_INSTALL_DIR/Eagle Grid Saver.app"

echo "$INSTALL_DIR/EagleGridSaver.saver"
echo "$APP_INSTALL_DIR/Eagle Grid Saver.app"
