#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then
  echo 'Xcode checks require macOS. No install or build was attempted.' >&2
  exit 1
fi
xcodebuild -version
swift test
python3 scripts/verify_project.py
xcodebuild -project Steady.xcodeproj -scheme Steady -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData \
  ARCHS="$(uname -m)" CODE_SIGNING_ALLOWED=NO build
echo 'Core Swift tests and unsigned simulator build completed. Device signing and UI checks remain separate.'
