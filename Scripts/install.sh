#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SAVER_PATH="$("$PROJECT_DIR/Scripts/build.sh")"
APP_PATH="$PROJECT_DIR/dist/Eagle Grid Saver.app"
INSTALL_DIR="/Library/Screen Savers"
APP_INSTALL_DIR="/Applications"

sudo mkdir -p "$INSTALL_DIR"
sudo rm -rf "$INSTALL_DIR/EagleGridSaver.saver"
sudo ditto --norsrc "$SAVER_PATH" "$INSTALL_DIR/EagleGridSaver.saver"

sudo mkdir -p "$APP_INSTALL_DIR"
sudo rm -rf "$APP_INSTALL_DIR/Eagle Grid Saver.app"
sudo ditto --norsrc "$APP_PATH" "$APP_INSTALL_DIR/Eagle Grid Saver.app"

sudo zsh "$PROJECT_DIR/Scripts/postinstall"

echo "$INSTALL_DIR/EagleGridSaver.saver"
echo "$APP_INSTALL_DIR/Eagle Grid Saver.app"
