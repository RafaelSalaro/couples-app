# Changelog

Newest first. One short entry per work package.

## 2026-11-13 — WP-1 Repo and project skeleton

- Monorepo layout: `ios/`, `supabase/`, `web/`, `android/` (empty), `docs/`.
- iOS: XcodeGen spec (`ios/project.yml`) with the app and five extension targets (Monitor, ShieldConfig, ShieldAction, Report, Widgets), shared App Group, entitlements, and Swift packages per `06-ios-app.md` §3 (DesignSystem, Core, Backend, Blocking, QRCode, Purchases, Features with one module per feature). `supabase-swift` and RevenueCat are wired in.
- Placeholders in one file, `ios/Config/Shared.xcconfig`: bundle prefix `com.example`, display name "Couples App", domain `example.com`. `AppBrand` reads the display name from the bundle.
- Supabase local project initialised (`supabase/config.toml`).
- CI workflows for iOS, backend and web; scripts `scripts/ios-build.sh` and `scripts/ios-test.sh`.
- Verified locally: app and all extensions build for the Simulator with no warnings; 16 placeholder package tests pass.
- Not included: the optional NotificationService target (add it when a work package needs it).
- Tooling choices recorded in `02-decisions-log.md` (E1–E3).
