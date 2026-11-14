# Changelog

Newest first. One short entry per work package.

## 2026-11-13 — W1 Waitlist landing page

- `web/`: Astro static site. One config file (`src/config/site.ts`) holds the name, company, domain, prices and launch state; design tokens from `10-brand-and-design-system.md` as CSS custom properties in light and dark; self-hosted Fraunces and Instrument Sans.
- Home page with all sections of `09-website-and-seo.md` §4: hero with a CSS-only animated phone (protected time turning into a kudos moment), philosophy, scan / ask / earn cards, kudos moment, protected time, shared progress, privacy promise, pricing teaser (every price says it covers both partners), FAQ with `FAQPage` markup, waitlist. All motion is transform and opacity only and becomes a still image with Reduce Motion.
- Waitlist form posts `{email, source}` to the `waitlist_join` Edge Function (URL from `PUBLIC_WAITLIST_ENDPOINT`), with gentle messages for every outcome, a honeypot, and a plain "not open yet" message when no endpoint is set. `scripts/mock-waitlist.mjs` is a local test double of the documented contract.
- Privacy and terms placeholder pages; `/waitlist/confirmed/` for the double opt-in link; 404 page.
- Deep links: `/.well-known/apple-app-site-association` (invite paths `/i/*`, app ID from config) and `/.well-known/assetlinks.json` (empty until Android has a signing key); `/i/<token>` invite fallback page via a Cloudflare Pages rewrite; `_headers` sets content types and no-index, no-referrer, no-store on token routes.
- SEO base: unique titles and descriptions, canonical URLs, Open Graph images generated at build time, `Organization`, `WebSite`, `MobileApplication` and `BreadcrumbList` markup, sitemap, robots.txt. `scripts/check-site.mjs` runs inside `npm run build` and fails on SEO errors, broken links, third-party resources or hard-coded brand values.
- Verified locally: build clean; `astro check` 0 errors; 9 unit tests pass; browser end-to-end test of the form against the test double passes (9 steps, including the invite route and "no requests leave the site"); Lighthouse on `/` and `/privacy/`, mobile and desktop: 100 / 100 / 100 / 100 (performance, accessibility, best practices, SEO), LCP 0.8 s mobile; home page JavaScript 2.2 KB.
- **Still needs live accounts:** the real `waitlist_join` function and Resend double opt-in (backend lane; the form has only been run against the test double), a Cloudflare Pages project and a real domain, the Apple Team ID for the association file. Lighthouse ran against a local server, not the deployed site.
- Not done on purpose: no analytics script (see E7). Decisions E6–E7 in `02-decisions-log.md`.

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
