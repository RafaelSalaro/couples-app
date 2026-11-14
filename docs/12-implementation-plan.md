# 12 — Implementation plan

## 1. Reality check on the credit window (2026-11-13 → 2026-11-16)

The goal is to use the introductory Fable 5.2 credits to build as much of the app as possible before they expire on November 16. Unused credits are lost, so during the window the rule is: **write every line of code that can be written now, with Fable, and leave only what truly needs a device or an Apple account for later.**

The one hard constraint: **real Screen Time behavior needs a paid Apple developer account on a real iPhone**, and the LLC/organization account may take days to weeks (D-U-N-S, Apple verification). So the sprint:

- Builds everything that does not need a device: backend, ledger, all screens, flows, animations, purchases, widgets, website.
- Writes the real Screen Time code too (WP-11 code-only), behind `BlockingService`, so after the window only device testing and fixes remain.
- Leaves device verification, App Store submission and the Family Controls request (which needs the account) for after the window.

See §6 for the credit strategy.

## 2. Phases

| Phase | Goal | Exit criteria |
|---|---|---|
| 0. Setup (Day 1) | Repo, tooling, docs in place | Repo with `docs/`, `CLAUDE.md`, Xcode project skeleton, Supabase local stack, CI running |
| 1. Credit sprint (Nov 13–16) | All code that does not need a device, in three parallel lanes | WP-1 to WP-10, WP-11 code-only, WP-12 and WP-13 code, W1, W2 done; all tests green |
| 2. Accounts & device (in parallel, as soon as possible) | LLC → D-U-N-S → Apple org account → Family Controls requests | Account active; entitlement requested for 5 bundle IDs |
| 3. Real Screen Time | WP-11 device verification and fixes | All 17 device scripts pass on two iPhones |
| 4. Polish & premium | WP-12 to WP-14 | Paywall, widgets, Live Activity, accessibility, snapshots |
| 5. Beta | TestFlight with 5–10 couples, 3–4 weeks | Exit criteria in `07-testing-plan.md` §5 |
| 6. Launch | App Store release, website, waitlist email | Approved and live |
| 7. Android | `08-android-app.md` | Play Store live |

Website work (WP-W1, W2) runs in parallel from Phase 1; the waitlist page should be live in the first week.

## 3. Work packages for Claude Code

Each package: read the listed docs first, implement, write tests, meet the Definition of Done in `CLAUDE.md`. Use the most capable model where marked ★.

| WP | Title | Read | Deliverable | Acceptance |
|---|---|---|---|---|
| 1 | Repo and project skeleton | CLAUDE.md, 06 | Monorepo: `ios/`, `supabase/`, `web/`, `android/` (empty), `docs/`; Xcode project with all targets and App Group, Swift packages per 06 §3; CI workflows | Builds; CI green; placeholders for bundle IDs |
| 2 | Design system package | 10 | Color assets (light/dark), fonts, spacing, radii, buttons, cards, rings, motion helpers | Snapshot tests of components in both themes |
| 3 ★ | Database schema, RLS, SQL functions | 05 | Migrations for all tables, policies, grant/spend/expire/debt/reset/streak functions, seed challenges | pgTAP tests cover every case in 07 §3 |
| 4 ★ | Edge Functions | 04, 05 | All functions in 05 §3, APNs sender, Resend sender, RevenueCat webhook, cron jobs | Deno tests for success and error paths; idempotency tests |
| 5 | Auth and onboarding | 03 §2, 06 §5 | Sign in with Apple + magic link, onboarding flow on `MockBlockingService` | UI test: install → ready |
| 6 | Pairing | 03 §3 | Invite link/code/QR, accept, unpair, universal links handling | UI test with two seeded users |
| 7 ★ | Blocking service | 04 §3.1–3.2, 06 §4 | `BlockingService`, `ScreenTimeBlockingService`, `MockBlockingService`, all five Screen Time extensions with shared App Group state | Unit tests on schedule evaluation; mock UI flows pass; real implementation compiles |
| 8 ★ | Unlock methods | 03 §5–6, 04 §3.3–3.4 | Unlock sheet, QR show/scan with TOTP, ask-partner with actionable push, code entry, minutes spend, emergency, Live Activity countdown | Unit tests for TOTP and state machine; UI tests for each method |
| 9 ★ | Minutes, challenges, kudos | 03 §7–8 | Minutes screen with 7-day expiry chart, ledger history, reset proposals, challenge library, completion/confirmation, custom challenges, kudos with celebration animation | UI tests; animations follow 06 §6 |
| 10 | Home, schedule, reports, settings | 03 §4, §9–14 | Home screen, schedule editor with approval flow, weekly report, private report extension view, settings, export, account deletion | UI tests; account deletion verified against backend |
| 11 | Real device Screen Time | 06 §4, 07 §4 | Switch to `ScreenTimeBlockingService`; fix device-only issues; verify midnight crossing and 15-minute minimum | Device scripts 1–17 pass |
| 12 | Purchases | 03 §12, 06 §10 | RevenueCat, paywall, trial, restore, pair premium from backend, downgrade behavior | Sandbox purchase tests; partner sees premium |
| 13 | Widgets and notifications polish | 06 §7–8 | Widgets, notification categories, expiry reminders, weekly report notification | Manual checks on device |
| 14 | Accessibility, localization readiness, App Store package | 06 §11–12, 07 §7 | Dynamic Type, VoiceOver, Reduce Motion, privacy manifest, review notes, demo accounts | Accessibility audit passes; checklist complete |
| W1 | Waitlist landing page | 09, 10 | Astro site skeleton, hero, philosophy, how it works, waitlist form, privacy/terms placeholders, deep-link files | Lighthouse ≥ 95; form works end to end |
| W2 | Full website + first guides | 09 | All pages in 09 §3, structured data, sitemap, 6 guides | Search Console verified; no SEO errors |
| W3 ★ | Website visual and motion redesign | 09 §10, 10 | Reimagined visuals, motion, scroll storytelling and transitions across the existing site; polished light and dark themes with a theme switch; content unchanged | Guardrails in 09 §10 met in both themes on phone and desktop; reduced-motion experience complete; site builds and existing checks pass |

## 4. Sprint schedule (Nov 13–16), three parallel lanes

Run up to three Claude Code sessions at once, each in its own git worktree (separate folder, separate branch) so they never edit the same files. Merge each lane's branch to `main` when a package passes its tests.

| Day | Lane A — backend | Lane B — iPhone app | Lane C — website and content |
|---|---|---|---|
| Fri Nov 13 | WP-1 (repo skeleton, first, alone) → WP-3 database and minutes engine | WP-2 design system (after WP-1 merges) | W1 waitlist page |
| Sat Nov 14 | WP-4 server functions | WP-5 onboarding → WP-6 pairing | Challenge library content (60+ PG challenges, seed file) |
| Sun Nov 15 | WP-12 backend side (RevenueCat webhook, pair premium) + extra database tests | WP-7 blocking service → WP-8 unlock methods | W2 full site + first 6 guides |
| Mon Nov 16 | Full security review of backend (Fable) | WP-9 minutes, challenges, kudos → WP-10 home/schedule/reports/settings → WP-11 code-only, WP-12 app side, WP-13 | App Store listing copy, review notes, privacy policy and terms drafts |

**Final hours of Nov 16:** one Fable session reviews the whole codebase against `03-feature-spec.md` and writes a list of gaps to `docs/CHANGELOG.md`. Tag `sprint-end`.

Keep the Mac awake (`caffeinate -di claude`). Commit after each package.

## 5. Founder tasks in parallel (not code)

1. Confirm the LLC status and start D-U-N-S today.
2. Buy the domain (a neutral one is fine until the name is chosen; it can redirect later).
3. Answer the open questions in `13-risks-and-open-questions.md`.
4. Start recruiting beta couples.
5. Pick the name (trademark search first).

## 6. Fable 5.2 credit strategy (until 2026-11-16)

**Principles**
1. **Fable for everything during the window.** Credits expire unused, so the usual "cheap model for routine work" rule is suspended until Nov 16. After Nov 16, switch to the included models for routine work and keep Fable for hard problems only.
2. **No waiting on decisions.** Answer the open questions that affect the sprint (O3, O5, O6, O7, O8, O11, and prices O4) before the matching package starts. A wrong guess built with Fable is wasted credit.
3. **Parallel lanes** (§4) so three productive sessions run at once instead of one.
4. **No idle time.** Tell Claude Code not to wait on CI: run tests locally, push, and move on. Leave auto-continue at usage limits on. Keep the Mac awake.
5. **Small, focused sessions.** One work package per session; start a fresh session (`/clear`) between packages so the model is not re-reading old context.
6. **Check the credit balance each morning and evening.** If credits are running ahead of plan, keep going down the list; if they are running out, drop the "if credits remain" items below first.

**If credits remain after the main plan (in this order)**
1. More tests: edge cases for the minutes ledger, unlock state machine and time zones.
2. Animation and haptics polish for the signature moments (`06-ios-app.md` §6).
3. Snapshot tests of every screen in light/dark and large text.
4. Extra SEO guides (drafts for the next 6 weeks).
5. Detailed Android work packages (docs only, no Android code yet).

**What deliberately waits until after Nov 16** (needs an Apple account, a device, or real users): running on a real iPhone, Family Controls request, TestFlight, App Store submission, beta.
