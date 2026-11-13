# iPhone app

Swift 6, SwiftUI, minimum iOS 17. See `docs/06-ios-app.md`.

## Build and test

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml` and is not committed.

```sh
brew install xcodegen
cd ios && xcodegen generate && open CouplesApp.xcodeproj
```

From the repository root:

```sh
./scripts/ios-build.sh   # build the app and all extensions for the Simulator
./scripts/ios-test.sh    # run every package test in the Simulator
```

## Placeholders

The app name, company and domain are not final. They are set once in
`Config/Shared.xcconfig` (`APP_DISPLAY_NAME`, `BUNDLE_ID_PREFIX`,
`ASSOCIATED_DOMAIN`) and flow into every target's bundle ID, the App Group,
the entitlements and `AppBrand`.

Local secrets go in `Config/Secrets.xcconfig.local` (ignored by git); see
`Config/Secrets.xcconfig.example`.

## Layout

```
App/          entry point, AppBrand, app strings and assets
Packages/     DesignSystem, Core, Backend, Blocking, QRCode, Purchases, Features
Extensions/   Monitor, ShieldConfig, ShieldAction, Report, Widgets
Config/       xcconfig files (identifiers, placeholder brand name, secrets)
```

Feature modules are named `<Name>Feature` (for example `HomeFeature`) so they
never collide with model types such as `Schedule`.
