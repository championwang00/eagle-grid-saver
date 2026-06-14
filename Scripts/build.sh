#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist"
SAVER_DIR="$OUTPUT_DIR/EagleGridSaver.saver"
APP_DIR="$OUTPUT_DIR/Eagle Grid Saver.app"

cd "$PROJECT_DIR"

rm -rf "$SAVER_DIR"
mkdir -p "$SAVER_DIR/Contents/MacOS" "$SAVER_DIR/Contents/Resources" "$OUTPUT_DIR/modules"

clang \
  -fobjc-arc \
  -O2 \
  -bundle \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework Cocoa \
  -framework IOKit \
  -framework QuartzCore \
  -framework ScreenSaver \
  -framework ImageIO \
  Sources/EagleGridSaverObjC/*.m \
  -o "$SAVER_DIR/Contents/MacOS/EagleGridSaver"

cp "$PROJECT_DIR/Resources/Info.plist" "$SAVER_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/EagleGridSaver.icns" "$SAVER_DIR/Contents/Resources/EagleGridSaver.icns"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

clang \
  -fobjc-arc \
  -O2 \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework Cocoa \
  -framework IOKit \
  -framework QuartzCore \
  -framework ScreenSaver \
  -framework ImageIO \
  Sources/EagleGridSaverApp/*.m \
  Sources/EagleGridSaverObjC/EagleGridSaverView.m \
  -o "$APP_DIR/Contents/MacOS/EagleGridSaverApp"

cp "$PROJECT_DIR/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/AppResources/EagleGridSaver.icns" "$APP_DIR/Contents/Resources/EagleGridSaver.icns"

codesign --force --deep --sign - "$SAVER_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$SAVER_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$SAVER_DIR"
