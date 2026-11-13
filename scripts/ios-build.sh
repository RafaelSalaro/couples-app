#!/bin/bash
# Generate the Xcode project and build the app for the Simulator.
set -euo pipefail
cd "$(dirname "$0")/../ios"
xcodegen generate --quiet
DEST="${IOS_DESTINATION:-generic/platform=iOS Simulator}"
xcodebuild build -project CouplesApp.xcodeproj -scheme CouplesApp \
  -destination "$DEST" -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO "$@" | (command -v xcbeautify >/dev/null && xcbeautify || cat)
