# Changelog

Newest first. One short entry per work package.

## 2026-11-13 — WP-2 Design system package

- `ios/Packages/DesignSystem`: all 19 color tokens from `10-brand-and-design-system.md` §3 with light and dark values (`.foregroundStyle(.hearth)`, `ColorToken.hearth.uiColor`), the type scale on Fraunces and Instrument Sans with Dynamic Type scaling (`.textRole(.title)`), spacing, radii, warm shadow, motion tokens with Reduce Motion fallbacks (`.motion(_:value:)`, `.moveOrFade()`), haptics.
- Components: buttons (primary, secondary, quiet, glow, on-dusk, destructive), chip, card tones, progress ring with a spoken description, two-circles brand mark, avatar, stat tile, note banner (never red), text field, section header, row; celebration pieces (glow bloom, particle drift, coming together).
- Fonts are bundled as the variable TTF files from Google Fonts with their OFL licenses; if registration ever fails the system serif and sans fonts are used.
- Snapshot tests use a small in-repo helper (`SnapshotSupport`), not a third-party library. References live in `Tests/DesignSystemTests/__Snapshots__`; delete a PNG to re-record it. References are compared only on the iOS major version they were recorded on (iOS 27) and skipped elsewhere.
- Tests: 16 pass (palette values, WCAG AA contrast of every text pairing in both themes, font registration, scale, motion, component gallery snapshots in light, dark and largest text). App and extensions build with no warnings.

## 2026-11-13 — WP-1 Repo and project skeleton

- Monorepo layout: `ios/`, `supabase/`, `web/`, `android/` (empty), `docs/`.
- iOS: XcodeGen spec (`ios/project.yml`) with the app and five extension targets (Monitor, ShieldConfig, ShieldAction, Report, Widgets), shared App Group, entitlements, and Swift packages per `06-ios-app.md` §3 (DesignSystem, Core, Backend, Blocking, QRCode, Purchases, Features with one module per feature). `supabase-swift` and RevenueCat are wired in.
- Placeholders in one file, `ios/Config/Shared.xcconfig`: bundle prefix `com.example`, display name "Couples App", domain `example.com`. `AppBrand` reads the display name from the bundle.
- Supabase local project initialised (`supabase/config.toml`).
- CI workflows for iOS, backend and web; scripts `scripts/ios-build.sh` and `scripts/ios-test.sh`.
- Verified locally: app and all extensions build for the Simulator with no warnings; 16 placeholder package tests pass.
- Not included: the optional NotificationService target (add it when a work package needs it).
- Tooling choices recorded in `02-decisions-log.md` (E1–E3).
