#!/bin/bash
# Generate the Xcode project and run every package test in the Simulator.
# Pass extra xcodebuild arguments, e.g. -only-testing:CoreTests
set -euo pipefail
cd "$(dirname "$0")/../ios"
xcodegen generate --quiet
if [ -z "${IOS_DESTINATION:-}" ]; then
  NAME=$(xcrun simctl list devices available | grep -oE 'iPhone [^(]+' | head -1 | sed 's/ *$//')
  IOS_DESTINATION="platform=iOS Simulator,name=${NAME}"
fi
xcodebuild test -project CouplesApp.xcodeproj -scheme CouplesApp \
  -destination "$IOS_DESTINATION" -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO "$@" | (command -v xcbeautify >/dev/null && xcbeautify || cat)
