# CLAUDE.md — instructions for Claude Code

Read this file at the start of every session. The full documentation lives in `docs/` in this repository and is mirrored in the claude.ai Project "Couples app". If the two ever differ, stop and ask which is current.

## What we are building

A couples app that pauses distracting apps on a shared schedule and lets partners unlock time together through three methods: in-person rotating QR code, partner approval (push or email), and minutes earned through shared challenges and partner "kudos". iPhone first (SwiftUI), Android later (Kotlin + Jetpack Compose), Supabase backend, static marketing website (Astro).

## The one principle that overrides everything

**This app is not about control. It is about being intentional and real connection.**

Every feature, string, color and animation must pass this test. Concretely:

- Everything is mutual. Both partners have identical powers. There is no "admin" partner.
- Either partner can unpair at any time, instantly, without the other's approval.
- Partners never see which apps the other blocked, what they did in an app, where they are, or detailed usage. They see only what the app itself creates: minutes, unlock requests, challenges, kudos, streaks.
- Celebrate, never scold. No red "denied" states, no shaming copy, no punishment animations. Red is reserved for truly destructive actions (delete account, unpair confirmation).
- An emergency unlock is always available.
- Use the vocabulary in `docs/10-brand-and-design-system.md` (for example "protected time", never "blocked"; "ask your partner", never "request permission").

## Which document to read for which task

| Task | Read first |
|---|---|
| Any product or behavior question | `docs/03-feature-spec.md`, then `docs/02-decisions-log.md` |
| Backend, database, server functions | `docs/05-data-model-and-api.md`, `docs/04-architecture.md` |
| iPhone app code | `docs/06-ios-app.md`, `docs/10-brand-and-design-system.md` |
| Tests | `docs/07-testing-plan.md` |
| Android | `docs/08-android-app.md` |
| Website | `docs/09-website-and-seo.md`, `docs/10-brand-and-design-system.md` |
| What to build next | `docs/12-implementation-plan.md` |

If a document and the code disagree, stop and ask. If a document is silent, check `docs/13-risks-and-open-questions.md`; if still unresolved, ask rather than invent product behavior.

## Stack (decided)

- **iOS:** Swift 6, SwiftUI, minimum iOS 17. Apple Screen Time frameworks: FamilyControls, ManagedSettings, ManagedSettingsUI, DeviceActivity. WidgetKit + ActivityKit. StoreKit 2 via RevenueCat SDK.
- **Backend:** Supabase (Postgres + Row Level Security, Auth, Edge Functions in TypeScript/Deno, pg_cron, Realtime). Free tier during build and beta.
- **Push:** APNs directly from Edge Functions (token-based auth). Android later via FCM.
- **Email:** Resend (free tier).
- **Subscriptions:** RevenueCat (entitlements shared to the partner server-side).
- **Website:** Astro static site on Cloudflare Pages.
- **Android (later):** Kotlin, Jetpack Compose, UsageStatsManager + foreground service + overlay activity, VpnService for web domains. Never AccessibilityService.

## Conventions

- **The app name is not final.** Never hard-code it. Use `AppBrand.displayName` (iOS), a single config value on the website, and `APP_NAME` env on the backend. Bundle IDs use the placeholder `com.<company>.couplesapp` until the company and name are final.
- **Money and minutes are integers.** Minutes are stored as whole minutes. All times are stored in UTC (`timestamptz`); schedules are evaluated in the user's local time zone.
- **Server is the source of truth for minutes, pairs and premium.** The phone caches state for offline use but every balance change is a server ledger entry, except the offline QR unlock, which is recorded locally and synced.
- **Screen Time tokens never leave the device.** `FamilyActivitySelection` and `ApplicationToken` values are stored only in the App Group container on that phone.
- **Accessibility:** support Dynamic Type, VoiceOver labels on every control, and Reduce Motion (replace motion with fades).
- **Localization-ready:** all strings in String Catalogs from day one. English only at launch; Portuguese (Brazil) is the likely second language.
- **No third-party analytics or ad SDKs.** Product events go to our own Supabase `events` table, no personal content.
- **Secrets** live in Supabase secrets and Xcode build configuration files excluded from git. Never commit keys.

## Model usage (cost control)

- **Until 2026-11-16 (introductory credit window):** use Fable 5.2 for all work. Credits expire unused. Follow the sprint lanes and credit strategy in `docs/12-implementation-plan.md` §4 and §6. Do not wait on CI; run tests locally and move on.
- **After 2026-11-16:** use Fable 5.2 only for architecture, Screen Time integration, the minutes ledger and its tests, the unlock state machine, security reviews, and complex animations. Use the default model for routine screens, copy, settings and refactors.

## Definition of done for any work package

1. Code builds with no warnings in the touched module.
2. Unit tests for all logic added; all tests pass.
3. Strings are in the String Catalog; colors and fonts come from design tokens.
4. Behavior matches `docs/03-feature-spec.md`; any deviation is recorded in `docs/02-decisions-log.md`.
5. A short note is added to `docs/CHANGELOG.md` (create it if missing).
