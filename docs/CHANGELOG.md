# Changelog

Newest first. One short entry per work package.

## 2026-11-15 — WP-12 Purchases (backend side)

- `revenuecat_webhook`: checks RevenueCat's Authorization header (constant-time), applies each event once (`webhook_events`), maps purchase, renewal, trial, product change, cancellation (premium stays to the end of the period), billing issue, expiry, lifetime and transfer to `entitlements`, ignores events older than the newest applied, and recomputes the pair's coverage. Anonymous RevenueCat ids are skipped; the app logs in with our user id.
- Pair premium from WP-3 (`recompute_coverage`, `is_premium`, the `pair_premium` view): one payer covers both, one trial per pair, the covered partner changes at most once per 30 days, the payer keeps premium after an unpair.
- Tests: 2 Deno tests on the event mapping and secret check; pgTAP premium cases in `pairing_premium_test.sql`.
- **Not verified:** against real RevenueCat events and App Store sandbox purchases (needs the accounts).

## 2026-11-15 — WP-4 Edge Functions

- 27 Edge Functions: the 22 signed-in functions the iPhone app calls (doc 05 §3 plus `revoke_invite`), each a thin wrapper that takes the caller from the JWT (never from the body), validates the body, calls its `api_*` SQL function and returns `{ok, data}` / `{ok:false, error:{code}}`; `waitlist_join` and `waitlist_confirm` for the website (CORS, rate limit, double opt-in, joining twice looks the same); `respond_unlock_by_token` for the web approve page (E8); `revenuecat_webhook`; `send_notifications`.
- Delivery: SQL queues notifications (respecting muted categories); `send_notifications` renders them in the brand voice and sends push through APNs with token auth (ES256 provider token, time-sensitive and actionable categories the app registers, silent push for a rotated QR secret, dead tokens removed) and email through Resend (the fallback email with the approve link and the 6-digit code issued at send time, waitlist confirmation, the optional weekly report email). Failures retry 5 times with a growing pause.
- Scheduled jobs (pg_cron, doc 05 §4): expire requests (every minute), expire minutes, expire completions and proposals, streak rollover, the 7 PM expiry reminder, the Sunday 7 PM weekly report (in the shape the app reads), pruning sent notifications, and the sender every minute through pg_net (needs two Vault secrets in a deployed project, see `supabase/README.md`).
- Realtime (doc 05 §5): triggers broadcast `{table, id}` on `pair:<pair_id>` for every table the app listens to; the app reads the row through RLS. Checked on the local stack.
- Bug found and fixed: account deletion failed when run as the service role ("permission denied for table minute_ledger"), because the ledger is immutable for that role; the deletion function now runs with the owner's rights, and a regression test runs it as the service role.
- Tests: Deno 28 (26 unit: auth, validation, error mapping without leaking database details, result shapes, CORS, APNs JWT and headers, outbox retries and dead tokens, copy that never scolds, email escaping; 2 integration tests against the local stack with real users and JWTs: pairing, the QR secret read through RLS, ask and Go for it, an idempotent minutes unlock, error codes, unpair, account deletion). pgTAP 145 in 6 files (21 new on the outbox, jobs, approve link and waitlist). `./scripts/functions-test.sh` runs the Deno tests.
- **Not verified:** real APNs and Resend delivery (need the Apple key and a Resend account), the deployed cron call (needs a Supabase project), and the iPhone app's `SupabaseBackend` against these functions end to end (the contract was matched by reading the app's calls; a run needs a configured project).

## 2026-11-15 — WP-3 Database: schema, RLS, SQL functions

- Completes WP-3 (part 1, the schema and seeds, was already on `main`). Five migrations: schema; privileges and Row Level Security; the minutes engine and streaks; premium, pairing and unlocks; schedules, challenges, kudos, export and account deletion.
- Minutes engine: every change is a ledger row (the ledger refuses edits); credits repay debt first, then become lots expiring in 7 days; spending takes the soonest-expiring lot first and checks debt, balance and the daily maximum in the person's local day; emergency borrow; hourly expiry; mutual reset; shared streak rollover. Each person's minutes are row-locked, two people always in the same order.
- One SQL function per Edge Function of doc 05 §3 (`api_<name>`), executable only by the service role: invites (code and link stored as hashes, 72 hours), accept (pair, QR secret, starting minutes), unpair (instant, minutes to zero, pending items cancelled), QR secret rotation; ask your partner (5 minutes, 3 per hour, push then email after 2 minutes or at once without push), Go for it / Let's wait, accountability code (issued only when the email goes, hashed, 5 attempts, single use), minutes unlock and emergency unlock (both idempotent by `client_event_id`), offline QR sync (idempotent, reused counter rejected, counter must match the start time); schedule changes (stricter now, looser to the partner for 24 hours, unpaired always now, 1 schedule free and 3 premium); challenges (done, one-tap confirm, shared grants both, 48 hours), custom challenge values, kudos (premium, 5–30, 60 per day); pair premium (one payer covers the pair, one trial per pair, covered partner changes at most once per 30 days, out-of-date webhook events ignored); export and account deletion.
- Tests: 123 pgTAP assertions in 5 files covering every case in `07-testing-plan.md` §3 (minutes, unlocks, schedules including both daylight-saving nights in New York, premium), plus pairing, challenges, kudos, deletion, and privileges and RLS (clients cannot call any engine function or write minutes; they read only their own and their partner's rows; only the current pair reads the QR secret; the anonymous role reads nothing). `scripts/db-concurrency-test.sh` runs two real sessions spending the same 30 minutes at once: exactly one succeeds.
- Docs: doc 05 gains `revoke_invite`, the `pair_secrets` read and the `pair_premium` view, which the iPhone app already uses; contract details recorded as E14.
- **Not done here:** the pg_cron schedule for the hourly jobs (`expire_minutes`, `expire_completions`, `streak_rollover`) and the outbox sender are part of WP-4. Streak milestones do not queue a celebration push yet. The web approve-link endpoint (E8) is not built: the token is issued and stored as a hash, but nothing redeems it until WP-4.
## 2026-11-14 — WP-13 Widgets and notifications

- Widgets, all read from the App Group (no network): small "Tonight" (protected-time status and your balance), medium "Together" (both balances and the streak), lock screen "Time left" (rectangular and inline: time left in protected time or in an unlock). Timelines are scheduled at the next phase changes, so they turn over at the right minute without the app running. Widgets use the brand faces by name, because WidgetKit cannot archive the variable fonts the app uses.
- Live Activity and Dynamic Island: the unlock countdown, started on every unlock, updated when it is extended, ended when it closes (or cleared next time the app opens).
- Notification categories with actions (06 §9): unlock request ("Go for it", "Let's wait"), completion ("Confirm"), schedule change ("Approve", "Let's talk"), all needing the phone unlocked. Taps open the right place: the unlock sheet, a request, a challenge, minutes, the weekly report, protected time.
- Change in this package: the Shield Action extension now has the Time Sensitive Notifications entitlement too, because it posts the time-sensitive "Ask {partner}" prompt itself; `ios/README.md` says to turn the capability on for that bundle ID as well.
- "Minutes expire tomorrow" (evening) and "weekly report ready" are server pushes from scheduled jobs (WP-4); the app's part is opening the Minutes screen and the weekly report from them, which is in place.
- Tests: the phase-change schedule widgets rely on (Core), push payload parsing into actions (Core), the links each notification opens. All 271 package tests and the 34 UI tests pass; the build has no warnings from our code.
- **Not verified, and the acceptance for this package (manual checks on a device):** widgets and the Live Activity on a home and lock screen, notification buttons, time-sensitive delivery through a Focus, push registration (needs the APNs key).

## 2026-11-14 — WP-12 Purchases (app side)

- Paywall from Us and from every premium preview: headline "One price for both of you", price lines "$39.99/year for both of you" and "$119.99 once, for both of you" (from the store, so localized), the 14-day trial for both when the pair has not used it, restore, and a footnote on what stays free and what happens if premium ends.
- `RevenueCatPurchasesService` (StoreKit 2) logs in with our user id, so the RevenueCat webhook can give premium to the pair on the server. The app never decides premium from the local receipt: after a purchase it asks the server for the pair's premium, waiting up to 5 seconds for the webhook, and otherwise picks up the change from the pair's live updates.
- Pending (Ask to Buy), cancelled and failed purchases all get calm copy. Settings shows who pays ("Premium for both of you. Paid by Ana.") and links to Apple's subscription management.
- Downgrade: minutes are kept; custom challenges and extra schedules rest and come back (Core `PremiumRules`). After an unpair, premium stays with the person who paid.
- Tests: Paywall 7, prices 3 and the simulated store 3 (unit); `UsUITests`: paywall trial purchase, restore and cancel. All 271 package tests and the 34 UI tests pass.
- **Not verified, and the acceptance for this package:** sandbox purchases and the partner receiving premium need App Store Connect products, a RevenueCat project with the `premium` entitlement, and the webhook (WP-12 backend side). Until then the demo uses a simulated store; with no RevenueCat key configured, a real build shows the paywall as unavailable instead of selling.

## 2026-11-14 — WP-11 Real device Screen Time (code only)

- Everything that can be done without a device is done: Release builds use `ScreenTimeBlockingService` (`BLOCKING_SERVICE = screentime`), Debug keeps the mock unless `-blockingService screentime` is passed, and the app plus its four Screen Time extensions carry Family Controls and the shared App Group (the five bundle IDs for the Family Controls request).
- New check: an unsigned Release build for a real iPhone (`IOS_DESTINATION="generic/platform=iOS" ./scripts/ios-build.sh -configuration Release`, now in `ios/README.md`). It succeeds. It showed one warning the Simulator build does not: "All interface orientations must be supported unless the app requires full screen". The app is iPhone-only and portrait-only, so it now declares `UIRequiresFullScreen`; the device and Simulator builds have no warnings from our code.
- Midnight crossing and the 15-minute minimum are covered by unit tests (WP-7); the midnight split is ready to switch on if a device shows one interval does not fire.
- **Open, and the acceptance for this package:** device scripts 1–17 in `ios/README.md`, on two iPhones, once the Apple developer account and the Family Controls entitlement exist. WP-11 stays open until they pass.

## 2026-11-14 — WP-10 Home, schedule, reports, settings

- Home scene (Tonight): both balances, today's protected time on the evening arc, the shared streak and recent activity, under the sky that follows protected time. The partner's status is neutral ("Protected time is off on Ana's phone"), never usage.
- Us place: one list leading to minutes, the week, protected time and settings.
- Schedule editor: start, end, days. Stricter changes (more hours, more days, more apps) apply now; looser ones ask the partner ("Ana would like protected time to start at 7 PM"), who can approve or "Let's talk". Unpaired, every change applies now. Premium allows up to 3 schedules. Paused apps open Apple's picker (the simulated one in the Simulator); fewer apps counts as looser.
- Weekly report: side by side and combined numbers, current week only on free; history, highlights and a trend on premium. The private card shows the person's own time in their paused apps through Apple's report extension, drawn inside its sandbox and never sent anywhere (decision T4); in the Simulator it explains what it will show.
- Settings: name, partner and unpair, relationship, daily maximum (15–240), notification categories (unlock and schedule requests cannot be muted), the weekly report email (off by default), subscription, export my data (a JSON file to share), delete account in two steps with the note that an Apple subscription is not cancelled and where to cancel it, privacy policy, terms, support and relationship safety, sign out.
- Tests: Reports 4, Schedule 7, Settings 9 model tests; `UsUITests` 10: home scene, neutral partner status, schedule editor and approval, the partner's schedule request, paused apps, weekly report, settings, delete account, paywall trial purchase, restore and cancel. All 271 package tests and the 34 UI tests pass.
- **Not verified:** account deletion against the real backend (acceptance asks for it; only the in-memory backend exists until WP-4, so `deleteAccount` is verified there, including that the partner is unpaired); the report extension on a device. The 24-hour expiry of pending schedule changes is a server rule (WP-3/4). Profile photo is still not built (needs a storage contract in doc 05).

## 2026-11-14 — WP-9 Minutes, challenges, kudos

- Together, the third place: the challenge library by category (the 5 free presets; the full library for premium, a calm preview otherwise), challenge detail with "Done" and an optional note (280 characters), the partner's completions to confirm with one tap, and kudos.
- Completing: the partner confirms, then the minutes arrive; shared challenges grant both on one confirmation. Unconfirmed completions expire after 48 hours (model rule; the server enforces it in WP-3/4).
- Custom challenges (premium): title and 5–60 minutes; the partner approves the value or suggests another ("Ana added … — sounds right?").
- Kudos (premium): from a challenge or free-form, 5–30 minutes, capped at 60 minutes given per day, with an optional note.
- Minutes screen (from Us): both balances, a 7-day chart of what expires when with a spoken line per day, the ledger history, and the mutual reset (propose, accept or decline, waiting state).
- Signature moments: kudos received (the giver's light swells and its glow washes over the other); streak milestone; the expiry timeline. Each has a Reduce Motion version that fades.
- Fix in this package: the kudos celebration's minutes now actually count up (up to 12 steps, ending exactly on the amount); before, the number appeared all at once although the code described a count. With Reduce Motion the amount shows at once, and VoiceOver hears only the final amount.
- Tests: Challenges 8, Kudos 6 (1 new for the count), Minutes 6 and expiry timeline 4 model tests; `TogetherUITests` 7: challenge done and confirmed, confirming the partner's challenge, free-tier preview, giving kudos and a custom challenge, the kudos-received celebration, the minutes screen with a reset, an incoming reset. All 271 package tests pass.
- **Not built:** a photo on a completed challenge (spec §8 says "optional photo or note"); like the profile photo it needs a storage contract in doc 05. The expiry-eve notification belongs to WP-13.

## 2026-11-14 — WP-8 Unlock methods

- One unlock sheet for every method (feature spec §6): pick a length (15, 30 or 60 minutes, default 30; premium steps in 15-minute increments), then scan your partner's code, ask your partner, type an accountability code, use your minutes, or take the emergency unlock. Unlocking while unlocked extends the window.
- In person: "Show my code" shows a QR that changes every 30 seconds (TOTP from the pair secret in the Keychain). Scanning verifies it on the phone with no network, refuses a code already used, and records the unlock locally to sync later. Free, no limit.
- Ask your partner: optional reason, the partner gets "Go for it" / "Let's wait" in the app and as notification buttons. "Let's wait" reads "Ana says let's wait — maybe later?"; no answer in 5 minutes reads "No answer this time. You can try again or use your minutes." The 6-digit accountability code from the email fallback can be typed in; too many wrong tries ends that request gently.
- Minutes: spent from the balance, refused gently when the balance or the daily maximum would not allow it. Emergency: always offered, 15 minutes, once per rolling 7 days, may borrow; the partner sees a neutral note.
- The Live Activity counts the window down; extending updates the running activity instead of starting a second one.
- Fixes in this package: (1) answering from a notification button now waits for the answer to reach the server before returning to iOS, which can suspend an app it launched in the background as soon as the handler returns; (2) a notification tap or link that arrives on a cold launch, before the root view has started the launch, now waits for it instead of being dropped (the pause-screen "Ask Ana" → notification → unlock sheet path, device script 3); (3) while the app is open only the pause-screen prompt shows a banner, as the code's comment always said; other notifications go to the list and the scene shows what happened.
- Tests: TOTP, QR unlock, ask-partner state machine and unlock rules in Core, QRCode and UnlockFeature; 1 new test for the cold-launch tap. UI tests for each method (`UnlockUITests`, 8): pause screen → unlock sheet, ask with "Go for it", ask with "Let's wait", accountability code, scan the partner's code, use minutes, emergency unlock without a partner, answering an incoming request. All 270 package tests and the 34 UI tests pass.
- **Not verified:** actionable notifications and the Live Activity on a device; the email fallback, the 2-minute resend and the 3-requests-per-hour limit are server-side and wait for WP-4; the camera scanner (the Simulator stands in with a sample code).

## 2026-11-14 — WP-7 Blocking service

- `BlockingService` with two implementations: `MockBlockingService` (the Simulator, the demo and every UI test) and `ScreenTimeBlockingService` (FamilyControls, ManagedSettings, DeviceActivity). Which one runs comes from `BLOCKING_SERVICE` in the xcconfig files or the `-blockingService` launch argument; the Simulator always uses the mock.
- One named ManagedSettings store holds the pause: apps, categories and websites (including web categories), plus "can't delete the app" during protected time. The chosen tokens stay in the App Group and never leave the phone.
- Schedules become repeating Device Activity monitors: one for an every-day schedule, one per start weekday otherwise. Splitting at midnight (04 §3.1) is built and tested but off until a device shows it is needed.
- Unlocks clear the pause and start a one-off `unlock-<id>` monitor of at least 15 minutes; extending an unlock replaces the monitor. When the window ends, the Monitor extension puts the pause back only if protected time is still on.
- The four Screen Time extensions share one decision point, `ShieldController`, which reads the App Group state: Monitor (schedule and unlock boundaries, with a 90-second allowance for callbacks that arrive early or late), Shield Configuration (the dusk pause screen with time left, a rotating inviting line, "Ask {partner}" and "Not now"), Shield Action ("Ask" posts the time-sensitive notification that opens the unlock sheet), Report (WP-10).
- Screen Time access is checked at launch and each time the app becomes active; when it goes off or comes back the server is told, so the partner sees only a neutral status.
- Change in this package: `ShieldController` now puts up or takes down the pause through a small `ShieldTarget` seam (ManagedSettings on a phone), so the Monitor extension's decisions are unit tested.
- Fixes found while bringing the lane-B branch to green: the place bar did not respond while a pushed screen (for example a challenge) was showing, because the navigation stack's UIKit layer sat on top of it; the bar is now a bottom safe-area inset. In the demo, Ana now joins 4 seconds after an invite appears (was 1.2 s), so the code and share button can be seen first; this also removes a timing failure in `PairingUITests`.
- Tests: Blocking 26 (8 new on the Monitor decisions: early and late callbacks, protected time across midnight, an unlock ending inside and after protected time, the end of an unlock that was since extended, nothing paused before setup). All 269 package tests and the 34 UI tests pass. The build has no warnings from our code; Xcode's App Intents step prints "Metadata extraction skipped" for targets without App Intents, the same as on `main` before.
- **Not verified:** everything on a real iPhone (no developer account yet): device scripts 1–17 in `ios/README.md`, in particular whether one interval across midnight fires correctly and the limit on how many monitors iOS accepts (a schedule on 7 separate weekdays uses 7; with the midnight split, 14).
- The lane-B branch carries draft code for WP-8 to WP-10, WP-12 (app side) and WP-13. It is now on `main` because it builds and its tests pass, but each of those packages is closed only by its own entry in this changelog.

## 2026-11-14 — WP-6 Pairing

- Invite three ways: share a link (`https://<domain>/i/<token>`), a 6-character code, or a QR code of the link for in person. Invites last 72 hours and can be cancelled. Join by typing the code, scanning the QR in the app, or opening the link.
- Universal links and the URL scheme are handled in one place (`AppModel.open`): an invite link that arrives before sign-in is kept and used once the person can pair. The app's associated domain is the placeholder from `Shared.xcconfig`.
- Pairing complete: both see "You're now paired with Ana." as the two lights, each carrying an initial, meet. The pair's QR secret is fetched and stored in the Keychain; starting minutes arrive for both.
- Unpair from Us → Partner: one confirmation (the only red button besides account deletion), instant, no approval. The other partner gets the gentle note "Ana ended your pairing." Protected time stays on each phone, minutes reset to zero, history is kept, open requests are cancelled. "Renew unlock code" rotates the QR secret.
- Inviting while paired is not offered. Before pairing, the home scene is in "waiting for your partner" mode.
- Tests: Pairing 9 unit tests; UI tests with two seeded users (`PairingUITests`): invite and partner accepts, join with code (including a wrong code), join by scanning, invite link opens the app, unpair, partner unpairs — 6 pass.
- **Not verified:** universal links on a device (need the real domain's `apple-app-site-association` and the developer account); the camera scanner (the Simulator has no camera, so a sample code stands in).
- Reading of the spec to confirm: "pairing requires both to confirm" is implemented as one partner creating the invite and the other accepting it, which is what doc 05's `create_invite`/`accept_invite` provide.

## 2026-11-14 — WP-5 Auth and onboarding

- Foundations this package stands on (all in `ios/Packages`): `Core` (models for every table of doc 05, schedule evaluation with midnight crossing and daylight saving, stricter/looser classification, a mirror of the ledger rules, the ask-partner state machine, App Group shared state, deep links); `Backend` (the `Backend` protocol for doc 05, `SupabaseBackend`, and the in-memory `FakeBackend`/`FakeWorld` with a scripted partner); `Blocking` (`BlockingService`, `MockBlockingService`, the real `ScreenTimeBlockingService`, pause-screen copy); `QRCode` (TOTP, verification, QR rendering, scanner, Keychain store); `FeatureSupport` (the app model and shared views).
- Sign in with Apple and email magic link, both through the `Backend` protocol. In the demo build Apple sign-in resolves to a fixed person and the "email" link can be opened from the sign-in screen.
- Onboarding in the order of feature spec §2, on `MockBlockingService`: welcome, sign in, relationship type (Couple only), invite or join, notifications with the reason, Screen Time access, guidance and app choice (nothing pre-selected), protected time (default 6 PM–9 AM), starting minutes and daily maximum (30 and 60), ready. Progress survives a relaunch. Declining Screen Time is gentle: the picker is skipped and the home scene offers to turn it on later.
- The app runs in the Simulator without Supabase: with no project configured (or `-demo 1`) it uses the in-memory backend and a scripted partner, Ana. Launch arguments for scenarios are documented in `ios/App/Composition.swift`.
- `scripts/ios-strings.sh` keeps the String Catalogs in step with the code (`--check` for CI).
- Tests: Core 52, Backend 43, Blocking 18, QRCode 10, FeatureSupport 28, Onboarding 8 (unit); UI tests `OnboardingUITests`: install → ready, magic link, declining Screen Time — 3 pass. Build has no warnings.
- **Not verified:** real Sign in with Apple and real magic-link email (need the Apple developer account and a Supabase project); `SupabaseBackend` compiles but has not run against the Edge Functions, which are not built yet. Profile photo is not built (needs a storage contract in doc 05).
- An assumption to confirm: someone who declines Screen Time access during onboarding can finish onboarding and is offered it again on the home scene (the spec covers revoking later, not declining at the start).

## 2026-11-14 — App design direction: "Two lights, one evening"

Under decision B11 the app's look, navigation and motion were redefined before more screens are built. The direction is specified in `10-brand-and-design-system.md` §11 (with §4, §5 and §7 updated) and noted in `06-ios-app.md` §5. Nothing a feature does has changed; only how it is reached and shown.

- Concept, shared with the website: the logo's two circles are two living lights, you (Hearth) and your partner (Glow), always the same size and treatment. Every scene sits under a sky that follows protected time and the clock: daylight, golden hour (the 90 minutes before protected time, and during an unlock) and dusk (protected time, dark in both themes on purpose).
- `DesignSystem`: sky palettes and `EveningSky` with paper grain, `LightDisc` and `TwoLights`, `EveningArc` (the status ring as an arc with a light travelling along it), `PlaceBar` (floating navigation pill), `LightsMeetControl` (slide your light to your partner's), sky-aware text and buttons, paper cards, new radii (14/22/32), Fraunces italic and two new type roles, a five-word haptic vocabulary, drift/meet/light motion tokens. Fraunces italic (variable, OFL) is now bundled.
- Navigation: three places instead of a tab bar. Tonight (home scene) and Us exist now; Together arrives with challenges and kudos (WP-9).
- Rebuilt in the new direction: onboarding (one evening, from daylight to dusk, with the lights drawing closer as progress), pairing (two lights carrying your initials meet), the home scene, the unlock sheet, asking and answering as a gesture with an ordinary button beside it, and the unlock-started moment.
- Snapshots: all component references were re-recorded on purpose because the look changed, and six scene references were added (each sky in both themes).
- Tests: DesignSystem 20 pass, including WCAG AA checks of the text colors against every gradient stop of every sky in both themes. All 213 package tests and the 9 UI tests pass (details in the WP-5 and WP-6 entries); the build has no warnings.
- Not yet verified by eye on a device: haptics and the feel of the slide gesture (the Simulator has no haptics).

## 2026-11-14 — W3 Website visual and motion redesign

Concept, "One evening": the two circles of the logo live as two lights behind every page. On the home page they start far apart and follow the scroll until they overlap at the waitlist, while the page warms from daylight to golden hour (light theme) or from dusk to candlelight (dark theme). Content, copy, page list, structured data and the waitlist flow are unchanged.

- Themes: light and dark are both designed; the site follows the device setting and a switch in the header (a sun that becomes a crescent made of two circles) stores the visitor's choice. The new theme opens as a circle from the switch.
- Home page: staged hero headline, the philosophy line lights up word by word, the three unlock cards stack like a deck, a light travels through one day in the protected-time panel, the report and kudos cards celebrate when they come into view, and the finale sits where the two lights meet.
- Whole site: floating glass header (navigation moves to a bottom pill on phones), rounded panels over the sky, page-to-page transitions in which the two lights glide to each page's own resting place, pointer light on cards, button and logo hover states, and a small "circles meet" moment when a waitlist signup succeeds.
- Reduced motion and no JavaScript: every element shows in its finished state; nothing is hidden behind animation.
- Verified locally: `npm run build` (20 pages, 0 SEO errors), `astro check` 0 errors, 9 unit tests, the waitlist browser test (all steps), Lighthouse 100/100/100/100 on mobile and desktop for home, how it works, pricing, guides, one guide and about (mobile LCP 0.6–0.8 s, CLS ≤ 0.002), home page JavaScript 5.5 KB. Every page was reviewed in light and dark at phone (390 px) and desktop (1440 px) widths in headless Chrome.
- Not verified: real Safari and Firefox, and a real mid-range phone. Page transitions between pages need a browser with cross-document view transitions; others navigate normally.
- Decision E9 recorded.

## 2026-11-13 — Extra SEO guide drafts (doc 12 §6, item 4)

- Six more guides as drafts (`draft: true`, `plannedWeek` 1–6, 1,300–1,600 words each) in `web/src/content/guides/`: partner always on their phone, phone-free dinner, phones out of the bedroom, 75 conversation starters, weekend digital detox, phone-free morning routine. Drafts are not built, not in the sitemap and not linked.
- `npm run build:drafts` builds a preview with drafts into `dist-drafts/` and runs the site checks on it: 26 pages, no errors. The normal build is unchanged (20 pages).
- Each draft needs one read by the founder before publishing; the dinner guide cites one paper (checked against Crossref).

## 2026-11-13 — App Store copy, App Review notes, legal drafts

- `content/app-store/listing.md`: name-agnostic listing copy with `{{APP_NAME}}` placeholders: subtitle options, promotional text, full description (states that one price covers both partners, 18+, no medical claims, subscription terms), two keyword options, in-app purchase names, six screenshot captions, preview video outline, draft App Privacy answers. Character counts measured.
- `content/app-store/review-notes.md`: text for the App Review notes field (what the app does, why it needs Screen Time, how pausing and each unlock method work, that no usage data leaves the device, test path with demo accounts), the checklist of what must accompany it, and text for the Family Controls (Distribution) request. Everything that needs the real app or accounts is marked TO DO; in-app labels quoted from the spec must be checked against the submitted build.
- `content/legal/privacy-policy.md` and `content/legal/terms-of-service.md`: drafts written from `04-architecture.md` §5, `03-feature-spec.md` and `11-business-legal-launch.md` §4, with 18+ (P25) and weekly report email off by default (P24) as decided. **Both are clearly marked as drafts for attorney review and not in force.** Company name, address, effective date, governing law, dispute terms, liability cap, the meaning of "lifetime" and the waitlist retention period are bracketed placeholders, not invented.
- The website's `/privacy/` and `/terms/` pages now render these same files (one source), filling the brand tokens from the site config; the build fails on an unknown token.
- Verified: build clean, 0 SEO errors and 0 warnings, `astro check` 0 errors, Lighthouse 100 on all four scores for `/privacy/` and `/terms/`.
- Founder decisions parked in the files: App Store keyword option (with or without "blocker"), secondary category, how reviewers sign in to demo accounts and how protected time is made active during review.

## 2026-11-13 — W2 Full website and first guides

- All pages of `09-website-and-seo.md` §3: `/how-it-works/`, `/pricing/` (free vs premium table from spec §12; every price says it covers both partners), `/guides/`, `/about/`, `/support/` (help, contact, account deletion steps), `/safety/` (safety by design, how to step away, US helplines), `/press/`, plus the token routes `/i/<token>` and `/approve/<token>`. Privacy and terms are still the W1 placeholders until the legal drafts land.
- Six cornerstone guides (1,400–1,900 words each) as a content collection: phone-free date ideas, phubbing, evening routine for couples, pausing social media at night on iPhone, screen time agreements for couples, the science of attention and relationships. Each has an author line and date, a brand-style illustration, an FAQ block, a soft call to action and links to `/how-it-works/` and `/pricing/`.
- The science and phubbing guides cite seven published papers; titles, journals, volumes and pages were checked against Crossref on 2026-11-13. The summaries of findings are ours and should be read once by the founder against the papers.
- Structured data on every page (`Organization`, `WebSite`, `BreadcrumbList`; `MobileApplication` with offers on home and pricing; `FAQPage` on home, how it works, pricing, support and guides; `Article` on guides; `ItemList` on the guides index). No ratings or reviews are marked up because none exist.
- `scripts/check-site.mjs` now also checks guide links, heading order, glued inline text and `Article` fields. Astro's HTML compression is off because it dropped spaces before links.
- Verified locally: build clean, 20 pages (16 indexable, all in the sitemap), 0 SEO errors; `astro check` 0 errors; Lighthouse 100 / 100 / 100 / 100 on 12 pages, mobile and desktop (home, how it works, pricing, guides index, two guides, about, support, safety, privacy, terms, press); mobile LCP 0.6–0.8 s.
- **Open:** Search Console and Bing verification need the live domain. The founder's story on `/about/` is left out until the founder writes it (`web/src/data/founder-story.ts`). Press screenshots wait for the app. The web approval page has no backend yet (E-entry in the decisions log). The iPhone steps in the how-to guide should be checked on a device. The guide about pausing social media avoids the word "block" (brand vocabulary) although people search for it: a founder call on SEO versus voice.
- Helpline numbers on `/safety/` were checked on 2026-11-13 and need re-checking before launch.

## 2026-11-13 — Challenge library content

- `content/challenges/library.json`: 72 PG premium challenges for couples in the brand voice, 18 per category (together, solo kindness, offline fun, movement), each with title, short description, minute value (5–45) and shared or individual. None repeats the 5 free presets.
- `content/challenges/build-seed.mjs` validates the library (lengths, minute range, categories, duplicate titles against the library and the free presets, brand vocabulary) and generates `supabase/seeds/10_challenge_library.sql` in the format `supabase/README.md` asks for (`tier` premium, re-runnable with `on conflict … do nothing`). Edit the JSON, not the SQL; `--check` fails if the seed is out of date.
- Verified against the real schema: loaded both seed files in a rolled-back transaction on the local Supabase database; 72 rows inserted, a second run inserted 0, total presets 77.
- Minute values are editorial suggestions in line with the free presets (5–15 for small individual gestures, 20–30 for shared time, 45 for long outings); adjust in the JSON after beta feedback.

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
