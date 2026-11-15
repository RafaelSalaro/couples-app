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

Test counts at this state: iOS 275 package tests and 41 UI tests, no warnings from our code (Simulator and an unsigned Release device build); backend 185 pgTAP assertions, the concurrency script, 28 Deno tests including 2 integration tests against the local stack.

## 3. Next steps, in order

1. **Run the iPhone app against a real Supabase project**, then work through the production checklist in `docs/security-review-backend.md`. `SupabaseBackend` was matched to the functions by reading its calls, and the integration tests cover the main path, but the app has never talked to the real backend. Needs a Supabase project (founder).
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
- **Emergency unlock with minutes in hand:** the server takes the 15 minutes from the balance first and records debt only for any shortfall (with 40 minutes: balance 25, no debt, spending allowed). The iPhone app's offline mirror (`MinutesLedger`, used by the demo) records the full 15 as debt (balance 25, spending blocked until 15 are earned back). Spec §6.4 ("the balance can go negative and must be earned back") reads most naturally as the server's behaviour, but does not say. Production follows the server; decide, and the other side is changed to match.

## 6. Founder to-do (not code)

Apple developer account and the Family Controls request; Supabase, Resend and RevenueCat accounts; domain and hosting; final name and company; attorney review of `content/legal/`. Unchanged from before.
