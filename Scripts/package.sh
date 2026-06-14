#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist"
PKGROOT="$OUTPUT_DIR/pkgroot"
COMPONENT_DIR="$OUTPUT_DIR/components"
PKG_PATH="$OUTPUT_DIR/EagleGridSaver-0.8.1.pkg"

cd "$PROJECT_DIR"

"$PROJECT_DIR/Scripts/build.sh" >/dev/null
find "$OUTPUT_DIR/Eagle Grid Saver.app" "$OUTPUT_DIR/EagleGridSaver.saver" -name '._*' -delete

rm -rf "$PKGROOT" "$COMPONENT_DIR" "$PKG_PATH"
mkdir -p "$PKGROOT/Applications" "$PKGROOT/Library/Screen Savers" "$COMPONENT_DIR"

ditto --norsrc "$OUTPUT_DIR/Eagle Grid Saver.app" "$PKGROOT/Applications/Eagle Grid Saver.app"
ditto --norsrc "$OUTPUT_DIR/EagleGridSaver.saver" "$PKGROOT/Library/Screen Savers/EagleGridSaver.saver"
find "$PKGROOT" -name '._*' -delete
dot_clean -m "$PKGROOT"
xattr -cr "$PKGROOT"

pkgbuild \
  --root "$PKGROOT" \
  --identifier "com.chaopi.EagleGridSaver.pkg" \
  --version "0.8.1" \
  --install-location "/" \
  "$COMPONENT_DIR/EagleGridSaver-component.pkg"

productbuild \
  --package "$COMPONENT_DIR/EagleGridSaver-component.pkg" \
  "$PKG_PATH"

echo "$PKG_PATH"
