# 07 — Testing plan

## 1. Principles

- The minutes ledger, unlock rules and schedules are where bugs would hurt trust most. They get the most tests.
- Screen Time behavior cannot be tested in the Simulator. Everything else is built behind `BlockingService` so it can be.
- Every bug found in beta gets a regression test before it is fixed.

## 2. Test layers

| Layer | Tool | Scope | Runs |
|---|---|---|---|
| Database | pgTAP via Supabase CLI | Every SQL function: grant, spend, expire, debt, daily max, reset, streak rollover, RLS policies | Every commit (CI) |
| Edge Functions | Deno test against local Supabase | Each function's success and error paths, idempotency, rate limits, webhook signatures | Every commit |
| iOS unit | Swift Testing | TOTP generation/verification, time-zone math, schedule evaluation (including midnight crossing and daylight-saving changes), view models, request state machine | Every commit |
| iOS UI | XCUITest with `MockBlockingService` and a seeded local backend | Onboarding, pairing, each unlock method, challenges, kudos, paywall | Every pull request |
| Snapshot | Swift snapshot tests | Key screens in light/dark and at largest Dynamic Type | Every pull request |
| Device (manual) | Two real iPhones, scripts in §4 | Real Screen Time shielding, extensions, notifications, Live Activities | Each milestone and before every TestFlight build |
| Beta | TestFlight | Real couples in daily life | Phase 4 |

CI: GitHub Actions (free for private repositories within monthly minutes). macOS minutes cost more, so run iOS UI tests on pull requests only, and database and function tests on every push using Linux runners.

## 3. Critical unit and database test cases

**Minutes**
- Earned lots expire exactly 7 days later; spent minutes come from the soonest-expiring lot.
- Spending across two lots splits correctly.
- Daily maximum uses the user's local day (test a user in a UTC−5 time zone spending at 11:30 PM and 12:30 AM).
- Debt from an emergency unlock is repaid before new lots are created; spending is refused while in debt.
- Mutual reset requires both acceptances and expires everything first.
- Concurrent spends (two requests at once) never over-spend (row locks).

**Unlocks**
- Request expires at 5 minutes; approval after expiry fails.
- Accountability code: single use, 5 attempts max, hashed at rest.
- Offline QR sync is idempotent; reused counter is rejected.
- Emergency unlock once per rolling 7 days.

**Schedules**
- 18:00–09:00 is "protected" at 23:00, 02:00, 08:59 and not at 09:00 or 17:59.
- Daylight-saving transition days.
- Stricter change applies immediately; looser change waits for approval; unpaired user applies directly.

**Premium**
- Pair premium when payer is active; non-payer loses premium on unpair; covered-partner change blocked within 30 days; trial counted once per pair.

## 4. Manual device test scripts (two iPhones)

Run on: iPhone with the oldest supported iOS 17.x available, and one on the newest iOS.

1. **Fresh install and onboarding** to paired state on both phones.
2. **Protected time start:** set schedule to start in 2 minutes; confirm Instagram shows the custom pause screen on time with the app closed.
3. **Pause screen button:** tap "Ask {partner}" → notification appears → tapping opens the unlock sheet.
4. **QR unlock offline:** airplane mode on the requester; scan partner's code; apps open for 15 minutes; shields return within 1 minute after; sync after reconnecting.
5. **Ask your partner:** approve from the lock-screen notification; requester unlocks within 10 seconds.
6. **Email fallback:** partner with notifications off receives the email; code works once.
7. **Minutes unlock** and daily maximum refusal.
8. **Emergency unlock** with zero balance → balance negative; second attempt the same week refused.
9. **Midnight crossing:** schedule 23:50–00:20 protects through midnight.
10. **Website blocking:** instagram.com blocked in Safari during protected time.
11. **Deny app removal:** cannot delete the app during protected time.
12. **Authorization revoked** in iOS Settings → app detects on next open; partner sees status.
13. **Unpair** from one phone → other phone notified; minutes reset; protected time stays.
14. **Live Activity** shows and ends with the unlock.
15. **Reboot** the phone during protected time → shields still active after restart.
16. **Restore purchase** and partner premium sharing.
17. **Account deletion** completes and the partner is unpaired.

## 5. Beta plan (TestFlight)

- **Who:** 5–10 couples, including at least 2 mixed couples (one partner on Android uses the email approval path until Android exists), a range of ages and iPhone models.
- **Length:** 3–4 weeks. Internal testers first (up to 100, no review); then external testers by public link (first build gets a short Apple beta review).
- **Prerequisite:** Family Controls (Distribution) approval for all five Screen Time bundle IDs; without it, Screen Time features do not work in TestFlight builds.
- **Week 1:** onboarding and pairing; collect drop-off points.
- **Week 2–3:** daily use; in-app feedback button; a short survey each Sunday.
- **Week 4:** paywall and pricing test (sandbox purchases), final survey: "Did it feel controlling at any point?" (target: fewer than 10% say yes).
- **Exit criteria:** no crash-free-session rate below 99.5%; zero minute-balance discrepancies; pairing completion ≥ 70% among beta couples; every "felt controlling" report reviewed and addressed.

## 6. Performance and reliability targets

- Cold launch to home screen < 1.5 s on a 3-year-old iPhone.
- Unlock approval to apps opening < 10 s on a good network.
- Shield applied within 60 s of schedule start (Apple controls exact timing; measure and document).

## 7. App Review package

- **Review notes:** what the app does, why it needs Screen Time (personal digital wellbeing for couples), how blocking and each unlock method work, that no usage data leaves the device.
- **Two demo accounts already paired** (reviewers cannot easily pair with themselves), with instructions and a pre-filled minutes balance.
- **Screen recording** (2–3 minutes) of pairing, protected time, the pause screen and each unlock method.
- **Privacy policy URL** and support URL on the website.
- Checklist owner: founder; prepared during Phase 4, not at the last minute.
