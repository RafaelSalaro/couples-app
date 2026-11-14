# Handoff — state of the build

**Written:** 2026-11-14, when the build switched from Fable 5.2 to Opus. Everything below was checked against git at that moment. Nothing is running; no agents, no local Supabase stack.

Read this file first, then `CLAUDE.md`, `docs/12-implementation-plan.md` and `docs/CHANGELOG.md`. Delete this file (or replace it) once the in-progress branches below are merged.

## 1. Where things are

| Place | What it holds |
|---|---|
| `main` (GitHub and `~/Developer/couples-app`) | Everything finished and tested. Last commit: `WP-6: pairing` |
| Branch `lane-b-wip` | iPhone app work in progress, **untested** (§3) |
| Branch `lane-a-wip` | Backend work in progress, **untested** (§4) |
| Branch `w3-redesign` | Already merged into `main`; can be deleted |
| `.claude/worktrees/agent-a4bec…` | Local checkout of `lane-b-wip` (local branch `worktree-agent-a4bec5b8b602d95b3`) |
| `.claude/worktrees/agent-a69ac…` | Local checkout of `lane-a-wip` (local branch `worktree-agent-a69acc3de425fcfd8`) |
| `.claude/worktrees/agent-a91de…` | Old website lane checkout; finished and merged, can be removed |

The docs in `docs/` in the repository are the source of truth. The claude.ai Project "Couples app" is a mirror that this session could not write to; re-sync it from the repo.

## 2. Done and on `main`

| Package | Status |
|---|---|
| WP-1 Repo skeleton | Done |
| WP-2 Design system | Done, then reworked by the app design direction |
| App design direction, "Two lights, one evening" (B11, E10) | Done. Specified in `10-brand-and-design-system.md` §11 |
| WP-5 Auth and onboarding | Done on the in-memory backend and mock blocking service |
| WP-6 Pairing | Done on the in-memory backend |
| WP-3 Database | **Part 1 only:** schema migration, 5 preset challenges seed, seed column docs |
| W1, challenge library (72), W2 + 6 guides, App Store copy, review notes, legal drafts, 6 extra guide drafts | Done |
| W3 Website redesign, "One evening" | Done |

Each has a changelog entry with its test results and what was not verified. Test counts at the last green state on `main`: 213 iOS package tests, 9 iOS UI tests, website build with 0 SEO errors, 9 website unit tests, waitlist browser test passing.

## 3. iPhone app — in progress (`lane-b-wip`)

Three WIP commits on top of `main`, 63 files, about 3,700 lines. **None of it has been built or tested as a whole since it was written**; the last commit is edits that were mid-flight when work stopped. Treat it as a draft to finish, not as done.

What the WIP contains, by commit:

1. `WIP: together place, kudos, celebrations, notifications, live activity, widgets` — the third navigation place (Together: challenges and kudos), celebration moments, notification categories, Live Activity, widgets.
2. `WIP: schedule, reports, settings, paywall, purchases, report extension, UI tests` — schedule editor, reports, settings (the "Us" place), paywall and RevenueCat wrapper, the private report extension, `TogetherUITests`, `UnlockUITests`, `UsUITests`.
3. `WIP: in-progress edits at handoff (untested)` — 14 files being edited at the stop: Home, Challenges, Kudos, Minutes, Reports, Schedule, Settings views, `Typography.swift`, the widgets bundle, `PrivateUsageReport.swift`, UI test support, `ios/README.md`, `.github/workflows/ios.yml`.

The work ran ahead of the package order: code for WP-7 to WP-10, WP-12 (app side) and WP-13 exists in draft, but **no package after WP-6 has been closed** (no changelog entry, tests not confirmed).

**Next steps for the iPhone app, in order**

1. Check out `lane-b-wip`, run `./scripts/ios-build.sh` and `./scripts/ios-test.sh`, and fix until the build has no warnings and all tests pass. Always filter xcodebuild output (see `ios/README.md`).
2. Close the packages one at a time against their acceptance criteria in `12-implementation-plan.md` §3, each with a changelog entry, commit and push to `main`: WP-7 blocking service → WP-8 unlock methods → WP-9 minutes, challenges, kudos → WP-10 home, schedule, reports, settings → WP-11 code-only → WP-12 app side → WP-13 widgets and notifications.
3. Keep the "Two lights, one evening" direction (`10-brand-and-design-system.md` §11): design changes how features are reached and shown, never what they do.

**Useful facts**

- The Xcode project is generated: `cd ios && xcodegen generate` (E1). Placeholders live in `ios/Config/Shared.xcconfig` (E2).
- The app runs in the Simulator without Supabase, on `FakeBackend` with a scripted partner, Ana (E13). Launch arguments are documented in `ios/App/Composition.swift`.
- Strings are written as `L("English text")`; `scripts/ios-strings.sh --check` keeps the String Catalogs in step (E11).
- `SupabaseBackend` compiles but has never run against real Edge Functions, because they do not exist yet.
- Nothing has run on a real iPhone. Real Screen Time behavior, Sign in with Apple, universal links, the camera scanner, haptics and push all wait for the Apple developer account and a device.

## 4. Backend — in progress (`lane-a-wip`)

On `main`: `supabase/migrations/20261113180000_schema.sql`, the preset challenge seed, and `supabase/README.md`.

On `lane-a-wip` (one WIP commit, 14 commits behind `main`, rebase first): `20261113190000_rls.sql` (249 lines) and `20261113200000_minutes.sql` (511 lines). **Never applied or tested.** There are no pgTAP tests yet (`supabase/tests/` is empty).

**Next steps for the backend, in order**

1. Finish WP-3: review and apply the two migrations, write the remaining SQL functions (grant, spend, expire, debt, reset, streak) and the pgTAP tests for every case in `07-testing-plan.md` §3.
2. WP-4 Edge Functions (every function in `05-data-model-and-api.md` §3, APNs, Resend, RevenueCat webhook, cron jobs) with Deno tests. Include `waitlist_join`, which the website's form is waiting for (contract in `web/README.md`).
3. WP-12 backend side, then the backend security review (`docs/security-review-backend.md`).

Docker comes from OrbStack and is not on the default PATH: `export PATH="$HOME/.orbstack/bin:$PATH"` before `supabase start`.

The iPhone app was built against the contracts in doc 05. If the backend must deviate from doc 05, update doc 05 and the decisions log in the same commit.

## 5. Open questions for the founder

Recorded so they are not lost; none blocks the next steps above.

1. **Analytics:** doc 09 §2 names Cloudflare Web Analytics, `CLAUDE.md` rules out third-party analytics. Nothing is embedded (E7).
2. **The word "block" for SEO:** doc 09 targets it, the brand vocabulary forbids it. The site avoids it; `content/app-store/` offers keyword options with and without.
3. **App Store secondary category:** Health & Fitness in the draft, Productivity as the alternative.
4. **Reporting partner content:** should the app offer a way to report a concern? The docs do not say.
5. **App Review logistics:** demo account sign-in without a mailbox, and making protected time active during review.
6. **Declining Screen Time during onboarding:** built so the person can finish onboarding and is offered it again on the home scene. Confirm.
7. **"Pairing requires both to confirm":** built as one partner inviting and the other accepting. Confirm.
8. **Profile photo:** not built; needs a storage contract in doc 05.
9. **Web approval page endpoint** (`PUBLIC_APPROVE_ENDPOINT`, `{token, approve}`): a proposal for the backend, not a decided API (E8).

## 6. Founder to-do (not code)

- Apple developer account (LLC → D-U-N-S → enrollment), then the Family Controls request for the five bundle IDs.
- Supabase project, Resend account, RevenueCat account; a domain and hosting for the website; the Apple Team ID for the universal-links file.
- Final app name and company name, then change the placeholders in `ios/Config/Shared.xcconfig` and `web/src/config/site.ts`.
- Attorney review of `content/legal/`; the founder's story for the About page; read the six draft guides before publishing.

## 7. Model use after the switch

`CLAUDE.md` "Model usage" applies: after the Fable credit window, use the default model for routine screens, copy, settings and refactors, and keep Fable for architecture, Screen Time integration, the minutes ledger and its tests, the unlock state machine, security reviews and complex animations. The founder is saving Fable for a later UX improvement pass.

## 8. Prompt to start the next session

> Read `docs/HANDOFF.md`, `CLAUDE.md`, `docs/12-implementation-plan.md` and `docs/CHANGELOG.md`. Continue the iPhone app from branch `lane-b-wip`: get it building with no warnings and all tests passing, then close WP-7 onward one package at a time as described in the handoff, pushing each to `main` with a changelog entry. After that, continue the backend from `lane-a-wip`.
