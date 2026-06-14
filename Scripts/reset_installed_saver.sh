#!/bin/zsh
set -euo pipefail

echo "Stopping macOS screen saver/cache processes..."
killall legacyScreenSaver 2>/dev/null || true
killall ScreenSaverEngine 2>/dev/null || true
killall "System Settings" 2>/dev/null || true
killall WallpaperAgent 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

echo "Removing user-installed copies..."
rm -rf "$HOME/Library/Screen Savers/EagleGridSaver.saver"
rm -rf "$HOME/Applications/Eagle Grid Saver.app"

echo "Removing preferences and local display cache..."
rm -rf "$HOME/Library/Application Support/EagleGridSaver"
rm -f "$HOME/Library/Preferences/com.chaopi.EagleGridSaver.plist"
rm -f "$HOME/Library/Preferences/com.chaopi.EagleGridSaverApp.plist"
defaults delete com.chaopi.EagleGridSaver 2>/dev/null || true
defaults delete com.chaopi.EagleGridSaverApp 2>/dev/null || true

echo "Removing screen saver host container caches..."
CONTAINERS_DIR="$HOME/Library/Containers"
for container in "$CONTAINERS_DIR"/com.apple.ScreenSaver.Engine* "$CONTAINERS_DIR"/*legacyScreenSaver*; do
  [[ -d "$container" ]] || continue
  rm -rf "$container/Data/Library/Application Support/EagleGridSaver"
  rm -f "$container/Data/Library/Preferences/com.chaopi.EagleGridSaver.plist"
  rm -f "$container/Data/Library/Preferences/com.chaopi.EagleGridSaverApp.plist"
  rm -f "$container/Data/Library/Preferences/ByHost"/com.chaopi.EagleGridSaver*.plist 2>/dev/null || true
  rm -f "$container/Data/Library/Preferences/ByHost"/com.chaopi.EagleGridSaverApp*.plist 2>/dev/null || true
done

echo "Removing ByHost preference leftovers..."
rm -f "$HOME/Library/Preferences/ByHost"/com.chaopi.EagleGridSaver*.plist 2>/dev/null || true
rm -f "$HOME/Library/Preferences/ByHost"/com.chaopi.EagleGridSaverApp*.plist 2>/dev/null || true

echo "Removing system-installed copies. macOS may ask for your password..."
if [[ -d "/Library/Screen Savers/EagleGridSaver.saver" ]]; then
  sudo rm -rf "/Library/Screen Savers/EagleGridSaver.saver"
fi
if [[ -d "/Applications/Eagle Grid Saver.app" ]]; then
  sudo rm -rf "/Applications/Eagle Grid Saver.app"
fi

echo "Forgetting installer receipts when present..."
for receipt in \
  "com.chaopi.EagleGridSaver.pkg" \
  "com.chaopi.EagleGridSaverApp" \
  "com.chaopi.EagleGridSaver"; do
  if pkgutil --pkg-info "$receipt" >/dev/null 2>&1; then
    sudo pkgutil --forget "$receipt" >/dev/null
  fi
done

echo "Restarting preference cache..."
killall cfprefsd 2>/dev/null || true

echo "Done. Reinstall the app, reopen System Settings > Screen Saver, and choose Eagle Grid Saver again. If it still shows stale behavior, log out once or restart macOS once."
