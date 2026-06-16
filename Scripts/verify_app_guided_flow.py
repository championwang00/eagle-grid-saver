#!/usr/bin/env python3
import pathlib


def require(text, needle, message):
    if needle not in text:
        raise SystemExit(message)


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    source = project / "Sources/EagleGridSaverApp/main.m"
    text = source.read_text()

    required = {
        "EagleLastPreparedAppVersionKey": "app must remember the version that last prepared the index",
        "chooseLibraryButton": "choose library button must be addressable for state gating",
        "applyGuidedFlowState": "app must centralize onboarding/update button state",
        "hasUsableDisplayCacheForCurrentLibrary": "app must verify cache readiness before enabling start/settings",
        "needsIndexAfterVersionChange": "app must detect update installs that need a fresh index",
        "setAdvancedControlsHidden": "speed and column controls must be hidden until setup is ready",
        "updateSetupGuidanceWithLibraryReady": "setup guidance must describe the current required step",
        "Step 1: choose an Eagle library": "new installs must point users at library selection first",
        "Step 2: click Update Index": "update installs must point users at index refresh",
        "Step 3: click Settings": "system screen saver selection must be shown only after the index is ready",
        "saveLastPreparedAppVersion": "successful index builds must mark the current version prepared",
        "self.startScreenSaverButton.hidden = !indexReady": "start screen saver must be hidden until index is ready",
        "self.updateIndexButton.hidden = !hasLibrary || indexReady": "update index should be the only main action when a library exists but index is not ready",
    }
    for needle, message in required.items():
        require(text, needle, message)

    print("app_guided_flow=ok")


if __name__ == "__main__":
    main()
