#!/bin/zsh
set -euo pipefail
export COPYFILE_DISABLE=1

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/dist"
PKGROOT="$OUTPUT_DIR/pkgroot"
COMPONENT_DIR="$OUTPUT_DIR/components"
SCRIPTS_DIR="$OUTPUT_DIR/scripts"
COMPONENT_PLIST="$OUTPUT_DIR/component.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/AppResources/Info.plist")"
PKG_PATH="$OUTPUT_DIR/EagleGridSaver-$VERSION.pkg"

cd "$PROJECT_DIR"

"$PROJECT_DIR/Scripts/build.sh" >/dev/null
find "$OUTPUT_DIR/Eagle Grid Saver.app" "$OUTPUT_DIR/EagleGridSaver.saver" -name '._*' -delete

rm -rf "$PKGROOT" "$COMPONENT_DIR" "$SCRIPTS_DIR" "$COMPONENT_PLIST" "$PKG_PATH"
mkdir -p "$PKGROOT/Applications" "$PKGROOT/Library/Screen Savers" "$COMPONENT_DIR" "$SCRIPTS_DIR"

ditto --norsrc --noextattr --noacl --noqtn "$OUTPUT_DIR/Eagle Grid Saver.app" "$PKGROOT/Applications/Eagle Grid Saver.app"
ditto --norsrc --noextattr --noacl --noqtn "$OUTPUT_DIR/EagleGridSaver.saver" "$PKGROOT/Library/Screen Savers/EagleGridSaver.saver"
find "$PKGROOT" -name '._*' -delete
dot_clean -m "$PKGROOT"
xattr -cr "$PKGROOT"

cp "$PROJECT_DIR/Scripts/postinstall" "$SCRIPTS_DIR/postinstall"
chmod 755 "$SCRIPTS_DIR/postinstall"

pkgbuild --analyze --root "$PKGROOT" "$COMPONENT_PLIST" >/dev/null
/usr/bin/python3 - "$COMPONENT_PLIST" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    components = plistlib.load(f)

for component in components:
    if component.get("RootRelativeBundlePath") == "Applications/Eagle Grid Saver.app":
        component["BundleIsRelocatable"] = False
        component["BundleHasStrictIdentifier"] = True

with open(path, "wb") as f:
    plistlib.dump(components, f)
PY

pkgbuild \
  --root "$PKGROOT" \
  --component-plist "$COMPONENT_PLIST" \
  --filter '\.DS_Store$' \
  --filter '(^|/)\._' \
  --filter '(^|/)\.__' \
  --scripts "$SCRIPTS_DIR" \
  --identifier "com.chaopi.EagleGridSaver.pkg" \
  --version "$VERSION" \
  --install-location "/" \
  "$COMPONENT_DIR/EagleGridSaver-component.pkg"

productbuild \
  --package "$COMPONENT_DIR/EagleGridSaver-component.pkg" \
  "$PKG_PATH"

echo "$PKG_PATH"
