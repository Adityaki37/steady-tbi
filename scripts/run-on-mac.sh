#!/bin/sh
# Builds Steady for an iPhone simulator, installs and launches it. Needs macOS with Xcode already installed.
# It does not install software, sign in, or change any Apple account settings.
# Usage: scripts/run-on-mac.sh [--open]   (--open only opens Steady.xcodeproj in Xcode)
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then
  echo 'run-on-mac.sh needs macOS with Xcode. Nothing was installed or built.'
  exit 0
fi
if [ "${1:-}" = --open ]; then
  open Steady.xcodeproj
  exit 0
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  echo 'xcodebuild is not available. Install Xcode yourself and run: sudo xcode-select -s /Applications/Xcode.app' >&2
  exit 1
fi
echo "macOS: $(sw_vers -productVersion)"
xcodebuild -version
LINE=$(xcrun simctl list devices available | grep -m1 -E '^ +iPhone .*\([0-9A-F-]{36}\)' || true)
if [ -z "$LINE" ]; then
  echo 'No available iPhone simulator found. Add one in Xcode > Settings > Components or Window > Devices and Simulators.' >&2
  exit 1
fi
UDID=$(echo "$LINE" | grep -oE '[0-9A-F-]{36}' | head -1)
echo "Simulator: $(echo "$LINE" | sed 's/^ *//') "
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
BUILD_DIR="${STEADY_BUILD_DIR:-$HOME/Library/Developer/SteadyDerivedData}"
xcodebuild -project Steady.xcodeproj -scheme Steady -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY=- build
APP="$BUILD_DIR/Build/Products/Debug-iphonesimulator/Steady.app"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.aditya.steadydemo
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [ -d "$DEVELOPER_DIR/../Applications/DeviceHub.app" ]; then
  open -a "$DEVELOPER_DIR/../Applications/DeviceHub.app"
elif [ -d "$DEVELOPER_DIR/Applications/Simulator.app" ]; then
  open -a "$DEVELOPER_DIR/Applications/Simulator.app"
fi
echo "Steady is running on the iPhone simulator. Built app: $APP"
echo 'Next: use MANUAL_TESTS.md, or open Steady.xcodeproj in Xcode (scripts/run-on-mac.sh --open).'
