# 02 — Decisions log

Status key: **Decided** = confirmed by the founder. **Assumed** = a default chosen during documentation; build with it unless the founder changes it. **Open** = must be decided before the phase noted.

## Product

| # | Decision | Status |
|---|---|---|
| P1 | Central philosophy: "not about control; about being intentional and real connection" | Decided |
| P2 | Launch audience is couples only. Friends/family relationship type and groups come later; data model supports both from day one | Decided |
| P3 | Two relationship types planned (romantic, and friends/family) each with its own suggested-challenge set; v1 ships romantic only | Decided (v1 scope Assumed) |
| P4 | Launch "complete": all three unlock methods, minutes, challenges, kudos, reports and premium at v1 | Decided |
| P5 | Minutes are the only currency (no separate points) | Decided |
| P6 | Each earned minute expires 7 days after it is earned; a timeline shows what expires when | Decided |
| P7 | Users can set a daily maximum of minutes spent and a starting balance; spend any amount per unlock | Decided |
| P8 | Minutes can be reset to a standard amount only with both partners' acknowledgement | Decided |
| P9 | Default protected time: 6 PM to 9 AM every day (includes overnight on purpose) | Decided |
| P10 | Making the schedule stricter applies immediately; loosening it needs partner approval | Decided |
| P11 | Unlock requests stay valid 5 minutes; requester chooses the length; default 30 minutes; free options 15 / 30 / 60, premium any length in 15-minute steps | Decided |
| P12 | Minimum unlock length is 15 minutes (Apple DeviceActivity schedule minimum, see T6) | Assumed |
| P13 | Emergency unlock always available; it borrows minutes (balance can go negative) and must be earned back | Decided |
| P14 | Emergency unlock: 15 minutes, once per rolling 7 days, borrows 15 minutes, breaks the shared streak | Decided |
| P15 | The only "penalty" is a broken shared streak; never shaming copy or red states | Decided |
| P16 | Partner can mark the other's challenge complete unprompted (kudos) | Decided |
| P17 | Custom challenges: creator types the challenge and its minute value; partner approves the value before it can be earned | Decided |
| P18 | Partners see each other's banked minutes; a shared report shows combined and individual metrics | Decided |
| P19 | Social media blocked by default, including the matching websites; users choose more apps; vital apps never blocked | Decided |
| P20 | Accountability codes delivered by push and email only, never SMS | Decided |
| P21 | Content stays PG to simplify store approval | Decided |
| P22 | App name not decided; build with a placeholder | Decided |
| P24 | Weekly report email is off by default; the report arrives by push and in-app, and email is an opt-in in Settings (was O11) | Decided |
| P25 | Minimum user age is 18+ in the terms; App Store age rating 12+ (was O1) | Decided |
| P23 | Partner sees a neutral status ("Protected time is off on Ana's phone") if Screen Time permission is revoked | Decided |

## Monetization

| # | Decision | Status |
|---|---|---|
| M1 | One subscription covers both partners ("one pays, both get it") | Decided |
| M2 | On unpair, the payer keeps premium, the other drops to free | Decided |
| M3 | 14-day free trial, then graceful downgrade to free | Decided |
| M4 | Yearly plan plus a lifetime one-time purchase; no monthly plan at launch | Decided (no-monthly Assumed) |
| M5 | Free tier: pairing, protected time, all three unlock methods plus emergency unlock, 5 preset challenges with preset minutes, limited reports | Decided |
| M6 | Premium: full challenge library, custom challenges with custom minutes, kudos, full reports, extra schedules | Decided |
| M7 | Price points: **$39.99 per year and $119.99 lifetime, each one price for the couple (both partners covered)**. Every price shown anywhere (paywall, store listing, website) must say it covers both people | Decided |
| M8 | Covered partner can change at most once per 30 days (prevents subscription sharing) | Assumed |
| M9 | On unpair, history is kept, active minutes reset to zero | Assumed |

## Platforms and business

| # | Decision | Status |
|---|---|---|
| B1 | iPhone first; Android built after the iPhone app is great, close to or after launch | Decided |
| B2 | Minimum iOS 17 | Decided |
| B3 | Publish as a company (LLC) on both stores | Decided |
| B4 | Backend: cheapest option — Supabase Free tier during build and beta, upgrade to Pro ($25/mo) when needed | Decided |
| B5 | Website with SEO, clean design, crisp animations; SEO reviewed weekly | Decided |
| B6 | Build with Claude Code, using Fable 5.2 for the hard parts; bulk of the build targeted before 2026-11-16 | Decided |
| B7 | Interface: modern, polished animations and haptics, SwiftUI native | Decided |
| B8 | Brand colors and identity per `10-brand-and-design-system.md` | Decided |
| B9 | Website redesign (W3): the site must look distinctly modern and showcase ambitious, original visual design, motion and scroll-driven storytelling. Content and copy stay as they are; presentation is open. The implementer has broad creative latitude within the brand, accessibility and performance guardrails in `09-website-and-seo.md` §10 | Decided |
| B11 | App UI and UX: Claude Code (Fable 5.2) has full creative freedom over the app's visual design, navigation, layouts, interactions and motion, within the guardrails in `06-ios-app.md` §5 and the brand fixed core in `10-brand-and-design-system.md` §0. Screens in `06-ios-app.md` §6 are a functional inventory, not layouts. Already-built UI and the WP-2 design system may be evolved to fit the chosen direction | Decided |
| B10 | Website theme: the site follows each visitor's device light/dark setting, so a phone in dark mode shows the dark (evening) theme and one in light mode shows the cream theme. This is intended. Both themes must feel equally deliberate and designed, not one as an afterthought, and a visible theme switch lets visitors choose | Decided (switch Assumed) |

## Engineering

| # | Decision | Status |
|---|---|---|
| E1 | The Xcode project is generated with XcodeGen from `ios/project.yml` and not committed, so parallel work never conflicts in the project file. XcodeGen is a developer tool, not an app dependency | Assumed |
| E2 | Until the company and name are final, placeholders are: bundle prefix `com.example` (app ID `com.example.couplesapp`), display name "Couples App", domain `example.com`. All three are set only in `ios/Config/Shared.xcconfig` | Assumed |
| E3 | Feature modules are named `<Name>Feature` (for example `ScheduleFeature`) to avoid clashing with model type names | Assumed |
| E4 | Snapshot tests use a small in-repo helper (`SnapshotSupport` in the DesignSystem package) instead of a third-party library, to keep the dependency list at `supabase-swift` and RevenueCat. Reference images are compared only on the iOS major version they were recorded on | Assumed |
| E5 | Colors are defined in code as light/dark token pairs (`ColorToken`) rather than an asset catalog, so the same values serve SwiftUI, UIKit and the Screen Time extensions and can be contrast-tested. Fraunces and Instrument Sans are bundled as variable font files (SIL Open Font License, license files included); fonts are assets, not code dependencies | Assumed |
| E6 | Website: the brand name, company, domain, prices and launch state live only in `web/src/config/site.ts` (overridable by environment variables, same placeholders as E2); the build fails if a page hard-codes them. The site stays fully static: `/i/<token>` and `/approve/<token>` are served by fixed pages through Cloudflare Pages rewrites (`web/public/_redirects`), and the invite page never reads or sends the token | Assumed |
| E7 | Website loads nothing from third parties: Fraunces and Instrument Sans are self-hosted (Fontsource packages, SIL Open Font License), Open Graph images are generated at build time, and the build fails on any external script, style, font or image. Cloudflare Web Analytics (named in `09-website-and-seo.md` §2) is **not** embedded, because `CLAUDE.md` rules out third-party analytics; whether to turn it on is a founder decision | Assumed |
| E8 | Website guides never name the app or state a price in their body text (the name is not final); the page layout adds the call to action, links and prices from the site config. Guides are Markdown files in `web/src/content/guides/`; `draft: true` keeps one out of the build. The web approval page (`/approve/<token>`) is built ahead of its backend: it posts `{token, approve}` to `PUBLIC_APPROVE_ENDPOINT` and, until that exists, explains the 6-digit code. The endpoint contract is a proposal for the backend lane, not a decided API | Assumed |
| E9 | Website W3: motion runs on one small in-repo script (`web/src/scripts/motion.ts`, about 5 KB, no animation library). The theme is set before first paint from the visitor's stored choice (`localStorage` key `theme`), else the device setting; the switch stores the choice. On phones the main navigation is a pill at the bottom of the screen. Fraunces is loaded with its SOFT axis plus the italic (both self-hosted) for display type. `web/scripts/shots.mjs` takes review screenshots in both themes | Assumed |
| E10 | App design direction (B11): "Two lights, one evening", specified in `10-brand-and-design-system.md` §11. The app has three places (Tonight, Together, Us) on a floating pill instead of a tab bar; the home sky is chosen from protected time and the clock (golden hour = the 90 minutes before protected time and any unlock; dusk = protected time, dark in both themes); gestures (sliding your light to your partner's) always have an ordinary button beside them. Fraunces italic is bundled for scene statements | Assumed |
| E11 | String Catalogs: user-facing strings are written as `L("English text")` and the English text is the catalog key (Apple's default extraction style). `scripts/ios-strings.sh` collects them into each module's `Localizable.xcstrings`, because Xcode's automatic extraction does not run for Swift packages built from the command line; `--check` fails when a catalog is out of date. Interpolated values are always strings | Assumed |
| E12 | A schedule's weekdays are the days on which it starts; a schedule whose end is at or before its start runs into the next day. An edit is "looser" if it removes any protected minute of the week, even if it adds others (so shifting hours needs approval); pausing fewer apps is sent to the partner only as "fewer apps", with no detail. The premium length picker goes up to 240 minutes in 15-minute steps | Assumed |
| E13 | The app runs on an in-memory backend (`FakeBackend`/`FakeWorld`, mirroring the rules of docs 03 and 05) with a scripted partner whenever no Supabase project is configured or the `-demo`/`-uiTest` launch arguments are given; UI tests use it. `SupabaseBackend` implements the same protocol against doc 05 and the schema migration but has not run against the finished Edge Functions | Assumed |
| E14 | Backend contract details (WP-3): (1) every Edge Function of doc 05 §3 wraps one SQL function `api_<name>(p_user, …)` holding the rules, executable only by the service role, taking `p_now` for tests and raising business errors as SQLSTATE `CAERR` with the code as message; (2) current pair members may read their pair's QR secret in `pair_secrets` (the iPhone app reads it after pairing and after a rotation); (3) `revoke_invite` cancels an open invite; (4) the view `pair_premium` tells a client whether its pair has premium; (5) the accountability code and the email approve token are created only when the fallback email is sent (`issue_unlock_email_secrets`), so nothing sits in the outbox in plain text; (6) the 3-requests limit counts requests created in the last hour; (7) a synced offline QR unlock's counter must match its start time within ±3 steps of 30 seconds; (8) the reset amount and the starting balance are bounded 0–60 minutes until the docs give a range | Assumed |

## Verified technical facts (checked 2026-11-13)

| # | Fact | Consequence | Source |
|---|---|---|---|
| T1 | Every target that uses Screen Time APIs (app plus each extension: Device Activity Monitor, Device Activity Report, Shield Action, Shield Configuration) needs its own **Family Controls (Distribution)** approval. Apple reviews manually; reports range from about 4 business days to a few weeks. Development builds work on a real device without approval | Request all bundle IDs on day one of having the developer account | [Newly: Family Controls entitlement](https://newly.app/how-to/family-controls-entitlement); [Apple forums](https://developer.apple.com/forums/thread/824726) |
| T2 | Only the **Account Holder** can submit the entitlement request | The LLC's account holder must do this | Same as T1 |
| T3 | A Shield's buttons cannot open the app. Supported responses are only none, defer, close | Shield "Ask your partner" button posts a local time-sensitive notification that opens the app | [Apple forums thread 793060](https://developer.apple.com/forums/thread/793060) |
| T4 | Screen Time usage data (Device Activity Report) cannot leave its sandbox, not even to our server | Shared reports use only app-created data; detailed usage is shown privately on each person's own phone | [Apple forums thread 727958](https://developer.apple.com/forums/thread/727958) |
| T5 | Apps are chosen only through Apple's picker; the app receives opaque tokens and cannot pre-select or gray out specific apps | Onboarding guides the user to pick the Social category; vital apps handled by guidance plus Apple's own protections | Apple FamilyControls docs |
| T6 | Device Activity schedules have a 15-minute minimum interval | Minimum unlock 15 minutes (P12). **Verify on device in Phase 1** | Widely reported developer behavior; verify |
| T7 | Supabase Free: 2 projects, 500 MB DB, 50k monthly active users, 500k Edge Function calls, 5 GB egress, pauses after ~1 week of low activity, **no backups** | Fine for build and beta; add our own nightly backup; upgrade to Pro before public launch or at first sign of real usage | [CostBench: Supabase Free](https://costbench.com/software/database-as-service/supabase/free-plan/) |
| T8 | Google Play personal accounts created after Nov 2023 need 12 testers for 14 days before production; **organization accounts with a D-U-N-S number are exempt** | The LLC choice removes this hurdle for Android | [onTest](https://ontest.app/blog/google-play-12-testers-14-days-requirement-explained) |
| T9 | Google Play restricts AccessibilityService to true accessibility tools; others need prominent disclosure, declarations and a video; reviewers reject blockers that could use narrower APIs | Android uses UsageStatsManager + foreground service + overlay activity, never AccessibilityService | [Google Play policy](https://support.google.com/googleplay/android-developer/answer/10964491?hl=en); [dev.to](https://dev.to/rexa/how-to-block-apps-on-android-without-an-accessibilityservice-5gog) |
| T10 | RevenueCat is free up to $2,500 monthly tracked revenue, then 1% | Use it for StoreKit, Play Billing and partner entitlement sharing | [CostBench: RevenueCat](https://costbench.com/software/subscription-billing/revenuecat/free-plan/) |
| T11 | Resend free: 3,000 emails/month, one domain | Enough for accountability-code email fallback and waitlist at launch | [CostBench: Resend](https://costbench.com/software/email-api/resend/free-plan/) |
| T12 | Apple organization enrollment needs a legal entity and a D-U-N-S number; D-U-N-S issuance and Apple's verification each commonly take days to weeks | The LLC path is on the critical path for on-device Screen Time testing and TestFlight | [Apple D-U-N-S help](https://developer.apple.com/support/D-U-N-S/index.html) |
| T13 | Apple requires in-app account deletion for apps with account creation | Build account deletion in v1 | App Store Review Guideline 5.1.1(v) |

## Change history

- 2026-11-13 — Initial log created from planning conversations of 2026-11-10 to 2026-11-13.
- 2026-11-13 — Founder confirmed O3–O8: all unlock methods free; emergency rules; custom challenge approval; unlock lengths; neutral partner status; prices, emphasized as one price for both partners.
- 2026-11-13 — WP-1: added engineering decisions E1–E3 (XcodeGen, placeholder identifiers, feature module naming).
- 2026-11-13 — Founder confirmed O11 (weekly report email off by default, P24) and O1 (minimum age 18+, App Store rating 12+, P25).
- 2026-11-13 — WP-2: added engineering decisions E4–E5 (in-repo snapshot helper; color tokens in code and bundled fonts).
- 2026-11-13 — W1: added engineering decisions E6–E7 (website config and static token routes; no third-party resources on the website).
- 2026-11-13 — W2: added engineering decision E8 (guides are name-free Markdown; web approval page built ahead of its backend).
- 2026-11-14 — Founder review of the deployed site: content approved; added B9 (W3 visual and motion redesign with creative latitude) and B10 (light/dark follows the device by design, both themes must feel intentional, theme switch).
- 2026-11-14 — W3 website redesign: added engineering decision E9 (motion script, theme storage, phone navigation, display font axes).
- 2026-11-14 — Founder: added B11 (full creative freedom for app UI and UX); `10-brand` now separates a fixed core from starting points; `06-ios-app` screens reframed as a functional inventory.
- 2026-11-14 — App design direction and iPhone foundations: added engineering decisions E10–E13 (app direction and places; string catalog workflow; schedule and looser-change rules on the phone; in-memory demo backend).
