#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist"
SAVER_DIR="$OUTPUT_DIR/EagleGridSaver.saver"
APP_DIR="$OUTPUT_DIR/Eagle Grid Saver.app"
SIGN_IDENTITY="${EAGLE_GRID_SAVER_SIGN_IDENTITY:-}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F '"' '/"Developer ID Application:|Apple Development:|Mac Developer:/{print $2; exit}'
  )"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  echo "warning: no Apple code signing identity found; using ad-hoc signing" >&2
fi

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

codesign --force --deep --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$SAVER_DIR"
codesign --force --deep --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$SAVER_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$SAVER_DIR"
