# Handoff — state of the build

**Written:** 2026-11-15, after the lane-B (iPhone) and lane-A (backend) branches were finished and merged. Read this file, then `CLAUDE.md`, `docs/12-implementation-plan.md` and `docs/CHANGELOG.md`.

## 1. Where things are

Everything is on `main`; there is no work in progress on any branch.

| Branch | State |
|---|---|
| `main` | All finished and tested work; the only branch (the merged lane branches and worktrees were removed on 2026-11-15) |

## 2. Work packages

| Package | Status |
|---|---|
| WP-1, WP-2, WP-5, WP-6, W1–W3, content | Done (earlier entries in the changelog) |
| WP-3 Database, RLS, SQL functions | Done: 145 pgTAP assertions, concurrency script |
| WP-4 Edge Functions | Done: 27 functions, outbox sender, jobs, realtime; 28 Deno tests |
| WP-7 Blocking service | Done |
| WP-8 Unlock methods | Done |
| WP-9 Minutes, challenges, kudos | Done |
| WP-10 Home, schedule, reports, settings | Done (deletion verified against the in-memory backend) |
| WP-11 Real device Screen Time | Code-only part done; device scripts 1–17 open |
| WP-12 Purchases | App and backend done; sandbox purchases open |
| WP-13 Widgets and notifications | Done; manual device checks open |
| WP-14 Accessibility, App Store package | Done in code: accessibility audit (4 UI tests), privacy manifests, demo-account script; reviewer sign-in, screen recording and device checks open |
| Backend security review | Done (Opus): `docs/security-review-backend.md`; production checklist needs the Supabase project |

Test counts at this state: iOS 288 package tests and 45 UI tests, no warnings from our code (Simulator and an unsigned Release device build); backend 225 pgTAP assertions, the concurrency script, 28 Deno tests including 2 integration tests against the local stack.

## 3. Next steps, in order

1. **Supabase project is live** (free plan, see `supabase/README.md` → Production project): migrations, seeds and the 27 functions deployed; 185 pgTAP assertions pass against production; `./scripts/live-smoke.sh` runs the app's main path against the deployed functions and passes. The Debug build of the app now uses it (`ios/Config/Secrets.xcconfig.local`, git-ignored). The four Auth values from the security review are set in the dashboard (site URL placeholder, redirect `couplesapp://login-callback`, 15-minute magic links, 12-character minimum password; founder, 2026-11-15). **Next for the founder:** change the site URL when the real domain exists; add APNs, Resend and RevenueCat when those accounts exist, and only then the two Vault secrets for the scheduled sender.
2. **App Review leftovers** (WP-14): a reviewer sign-in path without a mailbox (founder question 5), then run `supabase/demo/review_accounts.sql` on production and record the screen video.
3. With the Apple developer account: WP-11 device scripts, WP-12 sandbox purchases, WP-13 manual checks, APNs key.

## 4. Useful facts

- Docker comes from OrbStack: `export PATH="$HOME/.orbstack/bin:$PATH"`. On 2026-11-15 OrbStack's engine hung once and stopped the Supabase containers; `orb restart docker` recovered it after a long wait.
- Backend tests: `supabase test db`, `./scripts/db-concurrency-test.sh`, `./scripts/functions-test.sh` (from the repository root, with `supabase start` running).
- iOS: `./scripts/ios-build.sh`, `./scripts/ios-test.sh`; a failed UI-test wait now prints the screen's element tree in the log.
- Secrets and deployment of the functions: `supabase/README.md`.

## 5. Open questions for the founder

Unchanged from the previous handoff (analytics, the word "block" for SEO, App Store secondary category, reporting partner content, App Review logistics, declining Screen Time in onboarding, "pairing requires both to confirm", profile photo), plus:

- **Photo on a completed challenge** (spec §8) and the **profile photo**: both need a storage contract in doc 05.
- **Ranges** for the reset amount and the starting balance: bounded 0–60 minutes as a placeholder (E14).
- **An emergency remainder under 15 minutes on a real iPhone (O13):** pick one of the options in `13-risks-and-open-questions.md`. (The earlier question about borrowing with minutes in hand is settled: the app now borrows like the server, E17.)

## 6. Founder to-do (not code)

Apple developer account and the Family Controls request; Supabase, Resend and RevenueCat accounts; domain and hosting; final name and company; attorney review of `content/legal/`. Unchanged from before.
