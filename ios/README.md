# iPhone app

Swift 6, SwiftUI, minimum iOS 17. See `docs/06-ios-app.md` and, for the look and feel,
`docs/10-brand-and-design-system.md` §11 ("Two lights, one evening").

## Build and test

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml` and is not committed.

```sh
brew install xcodegen
cd ios && xcodegen generate && open CouplesApp.xcodeproj
```

From the repository root:

```sh
./scripts/ios-build.sh     # build the app and all extensions for the Simulator
./scripts/ios-test.sh      # run every package test and the UI tests in the Simulator
./scripts/ios-test.sh -skip-testing:CouplesAppUITests   # package tests only (about a minute)
./scripts/ios-test.sh -only-testing:CouplesAppUITests   # UI tests only (about ten minutes)
./scripts/ios-strings.sh   # update the String Catalogs from the code (--check to verify)
IOS_DESTINATION="generic/platform=iOS" ./scripts/ios-build.sh -configuration Release   # device build with real Screen Time, unsigned
```

Snapshot references live next to the tests in `__Snapshots__/`. To re-record one, delete
its PNG and run the test again.

## Running without a backend (the Simulator demo)

With no Supabase project configured the app runs on an in-memory backend with a scripted
partner, Ana, and on `MockBlockingService`. Everything resets on each launch. Launch
arguments (Edit Scheme → Arguments) choose the situation; they are documented at the top of
`App/Composition.swift`. Useful ones:

```
-demo 1 -scenario paired -phase protected            paired, inside protected time
-demo 1 -scenario paired -premium 1                  with premium
-demo 1 -scenario onboarded                          set up, not yet paired
-demo 1 -scenario paired -partnerActions sendKudos   Ana sends kudos a moment after launch
-demo 1 -scenario paired -partner silent             Ana does not answer
```

## Placeholders and configuration

The app name, company and domain are not final. They are set once in
`Config/Shared.xcconfig` (`APP_DISPLAY_NAME`, `BUNDLE_ID_PREFIX`, `ASSOCIATED_DOMAIN`)
and flow into every target's bundle ID, the App Group, the entitlements and `AppBrand`.

Local secrets go in `Config/Secrets.xcconfig.local` (ignored by git); see
`Config/Secrets.xcconfig.example`: the Supabase URL and anon key, and the RevenueCat key.

`BLOCKING_SERVICE` chooses the blocking implementation for device builds: `mock` in Debug,
`screentime` in Release. To try real Screen Time in a Debug build on a phone, set
`BLOCKING_SERVICE = screentime` in `Secrets.xcconfig.local` or pass the launch argument
`-blockingService screentime`. The Simulator always uses the mock.

## Layout

```
App/          entry point, composition, system services, notifications
Packages/     DesignSystem, Core, Backend, Blocking, QRCode, Purchases, Features
Extensions/   Monitor, ShieldConfig, ShieldAction, Report, Widgets
UITests/      XCUITests on the in-memory backend
Config/       xcconfig files (identifiers, placeholder brand name, secrets)
```

Feature modules are named `<Name>Feature` (for example `HomeFeature`) so they
never collide with model types such as `Schedule`. `FeatureSupport` holds the app model
and what every feature shares.

## Not yet verified on a device

Nothing below has been run on a real iPhone: there is no Apple developer account yet.
The real Screen Time code (`ScreenTimeBlockingService`, the five extensions) compiles and
its decisions are unit tested, but its behavior on a device is unverified. Work through
these with two iPhones (`docs/07-testing-plan.md` §4) once the account exists:

| # | Script | Status |
|---|---|---|
| 1 | Fresh install and onboarding to paired on both phones | Not verified |
| 2 | Protected time starts on schedule with the app closed; custom pause screen appears | Not verified |
| 3 | Pause screen "Ask {partner}" posts the notification; tapping opens the unlock sheet | Not verified |
| 4 | QR unlock offline, 15 minutes, shields return, sync after reconnecting | Not verified |
| 5 | Ask your partner: approve from the lock-screen notification; unlock within 10 s | Not verified |
| 6 | Email fallback with notifications off; code works once | Not verified (needs backend email) |
| 7 | Minutes unlock and daily maximum refusal | Not verified |
| 8 | Emergency unlock with zero balance; second attempt the same week refused | Not verified |
| 9 | Midnight crossing: 23:50–00:20 protects through midnight | Not verified |
| 10 | Website blocking in Safari | Not verified |
| 11 | App cannot be deleted during protected time | Not verified |
| 12 | Authorization revoked in iOS Settings is detected; partner sees the status | Not verified |
| 13 | Unpair from one phone; the other is notified; minutes reset; protected time stays | Not verified |
| 14 | Live Activity shows and ends with the unlock | Not verified |
| 15 | Reboot during protected time; shields still active | Not verified |
| 16 | Restore purchase and partner premium sharing | Not verified (needs App Store Connect and RevenueCat) |
| 17 | Account deletion completes and the partner is unpaired | Not verified against the real backend |

Specific things to check first, because the code makes an assumption about them:

- **Midnight-crossing schedules** are registered as one repeating interval. If that does not
  fire correctly on some iOS version, set `SchedulePlanner.splitAtMidnight` to `true`
  (start–23:59 and 00:00–end); the Monitor extension already copes with both.
- **15-minute minimum** for unlock monitors (decision T6): `startUnlock` refuses anything
  shorter and undoes the unlock if the monitor cannot be registered.
- **Callback timing**: the Monitor extension looks 90 seconds ahead when a schedule or unlock
  boundary fires, in case iOS calls it slightly early (`ShieldController.callbackTolerance`).
- **Live Activity ending**: the app ends it when the unlock ends if it is still running;
  otherwise the activity is marked stale at the end time and cleared when the app next opens.
  Ending it exactly on time with the app closed would need a push from the server.
- **Widgets and notifications**: widget timelines, the notification categories and their
  buttons, time-sensitive delivery and push registration need a device and the APNs key.
  Turn on Time Sensitive Notifications for both the app's and the ShieldAction extension's
  bundle IDs: the extension posts the time-sensitive "Ask {partner}" prompt itself.
- **Sign in with Apple, universal links, the camera scanner, haptics**.
