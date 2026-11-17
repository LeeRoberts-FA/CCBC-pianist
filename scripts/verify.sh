#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "Xcode version:"
xcodebuild -version
echo "Check Xcode project format:"
plutil -lint CCBCPianist.xcodeproj/project.pbxproj
echo "Build CCBCPianist for Mac (no distribution signing):"
xcodebuild \
  -project CCBCPianist.xcodeproj \
  -scheme CCBCPianist \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$PWD/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
echo "Build complete. App: $PWD/DerivedData/Build/Products/Debug/CCBCPianist.app"
