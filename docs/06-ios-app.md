# 06 — iPhone app

## 1. Baseline

- Swift 6 (strict concurrency), SwiftUI, Observation (`@Observable`), minimum iOS 17, iPhone only at launch (iPad not supported).
- Dependencies (Swift Package Manager): `supabase-swift`, `RevenueCat` (purchases-ios). Nothing else without a recorded decision.
- Design tokens from `10-brand-and-design-system.md` implemented as a `DesignSystem` package (colors with light/dark, fonts, spacing, radii, motion).

## 2. Targets and bundle IDs

| Target | Bundle ID (placeholder) | Frameworks | Needs Family Controls approval |
|---|---|---|---|
| App | `com.<company>.couplesapp` | SwiftUI, FamilyControls, ManagedSettings, DeviceActivity, StoreKit | Yes |
| DeviceActivityMonitor | `…couplesapp.monitor` | DeviceActivity, ManagedSettings | Yes |
| ShieldConfiguration | `…couplesapp.shieldconfig` | ManagedSettingsUI | Yes |
| ShieldAction | `…couplesapp.shieldaction` | ManagedSettings, UserNotifications | Yes |
| DeviceActivityReport | `…couplesapp.report` | DeviceActivity, SwiftUI | Yes |
| Widgets | `…couplesapp.widgets` | WidgetKit, ActivityKit | No |
| NotificationService (optional) | `…couplesapp.notifservice` | UserNotifications | No |

All targets share App Group `group.com.<company>.couplesapp` and Keychain access group for the QR secret (app only).

**Capabilities:** Family Controls, App Groups, Push Notifications, Sign in with Apple, Associated Domains (`applinks:<domain>`), In-App Purchase, Time Sensitive Notifications, Background Modes (remote notifications).

**Entitlement request:** submit Family Controls (Distribution) for all five Screen Time bundle IDs as soon as the LLC developer account exists (see `02-decisions-log.md` T1, T2).

## 3. Code structure

```
App/
  CouplesApp.swift           // entry, dependency container
  AppBrand.swift             // displayName and all brand strings in one place
Packages/
  DesignSystem/              // tokens, fonts, components (buttons, cards, rings)
  Core/                      // models, errors, date/time-zone utilities
  Backend/                   // Supabase client, Edge Function calls, Realtime
  Blocking/                  // BlockingService protocol + ScreenTimeBlockingService + MockBlockingService
  QRCode/                    // TOTP generation/verification, QR rendering, scanner
  Purchases/                 // RevenueCat wrapper, premium state
  Features/
    Onboarding/  Pairing/  Home/  Unlock/  Minutes/  Challenges/
    Kudos/  Reports/  Schedule/  Settings/
Extensions/
  Monitor/  ShieldConfig/  ShieldAction/  Report/  Widgets/
```

**BlockingService** (protocol) is the seam that lets most of the app be built and tested in the Simulator before the entitlement and a device are available:

```swift
protocol BlockingService: Sendable {
  func requestAuthorization() async throws
  var authorizationStatus: BlockingAuthorization { get }
  func saveSelection(_ selection: PausedAppsSelection) throws
  func applySchedule(_ schedules: [ProtectedSchedule]) throws
  func startUnlock(id: UUID, minutes: Int) throws      // min 15
  func endUnlockEarly(id: UUID) throws
  func isProtectedNow() -> Bool
}
```
`ScreenTimeBlockingService` uses FamilyControls/ManagedSettings/DeviceActivity. `MockBlockingService` simulates state in the App Group and shows a fake shield in debug builds.

## 4. Screen Time implementation notes

- Authorization: `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
- App selection: `FamilyActivityPicker` → `FamilyActivitySelection` (applications, categories, web domains). Encode and store in the App Group. Tokens are device-specific and never uploaded.
- Shielding: one named `ManagedSettingsStore(named: .protectedTime)`:
  - `shield.applications`, `shield.applicationCategories = .specific(categories)`, `shield.webDomains`, `shield.webDomainCategories = .specific(categories)` (covers social websites in Safari and other browsers that use WebKit).
  - `application.denyAppRemoval = true` during protected time.
- Schedules: `DeviceActivityCenter().startMonitoring(.protected(scheduleID), during: DeviceActivitySchedule(intervalStart:intervalEnd:repeats: true))`. Verify midnight-crossing behavior (fallback: split into two schedules).
- Unlocks: clear the store, then `startMonitoring(.unlock(id), during:)` from now to now + N minutes (≥ 15). In the Monitor extension's `intervalDidEnd` for `.unlock`, re-apply shields if any protected schedule is currently active.
- Shield Configuration: styled in brand colors within Apple's fixed layout (design open); title "Protected time", subtitle with time remaining (computed from the active schedule in the App Group), primary "Ask {partner}", secondary "Not now".
- Shield Action: primary → post a time-sensitive local notification "Tap to ask {partner} or use your minutes" (deep link `couplesapp://unlock`), respond `.close`; secondary → `.close`.
- Report extension: shows the user's own usage of paused apps during protected time this week. No data leaves the extension.
- Authorization loss: on every app launch and on `scenePhase` active, check `AuthorizationCenter.shared.authorizationStatus`; if revoked, show a gentle re-enable screen and report the status to the server (partner sees neutral status, subject to open question O5).

## 5. UI and UX creative direction

**Ambition.** The app should feel like one of the most beautifully designed apps on the iPhone: original, polished, emotionally warm and a joy to use every day. Claude Code (Fable 5.2) has **full creative freedom over UI and UX**: information architecture, navigation model, layouts, components, visual style, interaction patterns, transitions, haptics, sound and micro-interactions. Avoid stock or template-looking UI. Explore boldly; the guardrails below are the only fixed rules.

**What it should express.** Two people choosing time together. Protected time should feel like a calm, cozy evening, not a lock. Unlocking, earning minutes and receiving kudos should feel like small moments of warmth and appreciation. Both partners are visibly equal.

**Areas to explore (suggestions, not requirements)**
- A home screen that makes "us" the center: both partners, shared time and progress, in a way that feels alive.
- Unlock flows that feel like a gesture between two people rather than a form.
- Celebration moments (kudos, streak milestones, pairing) that are genuinely delightful.
- Data (minutes expiring, weekly reports) presented in ways that are clear, beautiful and encouraging.
- Use of modern iOS capabilities where they add value: rich transitions, materials, haptics, interactive widgets, Live Activities.

**Guardrails (fixed)**
- Behavior and rules: `03-feature-spec.md` and `02-decisions-log.md`. Design may reorganize *how* features are reached and presented, never *what* they do.
- Philosophy and safety rules in `CLAUDE.md` (mutual, no control, celebrate never scold, instant unpairing, emergency unlock always reachable).
- Brand fixed core and voice from `10-brand-and-design-system.md` §0 and §2.
- Accessibility: Dynamic Type up to accessibility sizes, VoiceOver, Reduce Motion, WCAG AA contrast in both themes, 44 pt touch targets.
- Native SwiftUI, smooth on supported devices (no dropped frames in signature moments), light and dark themes both first-class.
- Apple-controlled surfaces stay within Apple's limits: the app picker, permission prompts and the pause screen (shield), whose layout Apple fixes (icon, title, subtitle, two buttons, colors).
- Prices always shown as one price for both partners (decision M7).

**Chosen direction (2026-11-14):** "Two lights, one evening": a sky that follows the day and protected time, the two partners as two equal lights, three places (Tonight, Together, Us) instead of a tab bar, unlocking as a gesture with a button path. It is specified in `10-brand-and-design-system.md` §11 and implemented in the `DesignSystem` package.

## 6. Functional inventory

What each area must let people do. This is a checklist of required functions, not a layout: screens may be combined, split, reordered or reimagined, as long as every function is reachable and onboarding respects the permission order Apple requires.

| Area | Functions |
|---|---|
| Onboarding | Welcome/philosophy · Sign in · Relationship type · Invite or join · Notifications permission · Screen Time permission · Choose apps guidance + picker · Protected time · Starting minutes & daily max · Ready |
| Home | Both balances · protected-time status ring (time left or unlock countdown) · streak · "Unlock" button · today's activity feed |
| Unlock sheet | Choose length · four methods: Scan partner's code, Ask partner, Use minutes, Emergency |
| Show my code | Full-screen rotating QR with a 30-second progress ring |
| Scanner | Camera with guide frame, success animation |
| Requests | Incoming request card (Go for it / Let's wait) · outgoing status · enter code |
| Minutes | Balance, 7-day expiration timeline chart, ledger history, reset proposal |
| Challenges | Library by category · challenge detail · mark done · confirmations · custom challenge (premium) |
| Kudos | Give kudos sheet · received celebration |
| Reports | This week (individual + combined) · history (premium) · private Screen Time report |
| Schedule | Protected time editor · pending change approvals |
| Settings | Profile · partner & unpair · paused apps · daily max · notifications · subscription · export · delete account · support & safety |
| Paywall | Headline "One price for both of you", benefits, yearly ($39.99/year for both of you) + lifetime ($119.99 once, for both of you), trial, restore |

## 7. Signature moments

These moments deserve special design attention. The ideas in brackets are only examples of the intended feeling; the designer should invent the actual treatment.

1. **Kudos received** (warmth arriving, the minutes counting up).
2. **Unlock approved** (protected time gently opening).
3. **QR scan success** (two people meeting).
4. **Streak milestone** (shared pride).
5. **Minutes expiring timeline** (clear, calm, encouraging).
6. **Pairing complete** (two people coming together).

Fixed: never shaking, red flashes or "denied" sounds; every moment has a Reduce Motion equivalent.

## 8. Widgets and Live Activity

Required content below; design and any additional widget ideas are open.

- Small widget: protected-time status and your balance.
- Medium widget: both balances and streak.
- Lock-screen widget: time left in protected time or unlock.
- Live Activity + Dynamic Island: unlock countdown, started on every unlock, ends automatically.

## 9. Notifications

Categories with actions:
- `UNLOCK_REQUEST`: actions "Go for it", "Let's wait" (authenticated action, calls `respond_unlock_request`).
- `COMPLETION_CONFIRM`: action "Confirm".
- `SCHEDULE_CHANGE`: "Approve", "Let's talk".
Time-sensitive interruption level for unlock requests and the shield prompt. Requires the Time Sensitive Notifications capability.

## 10. Deep links and universal links

- `https://<domain>/i/<token>` → accept invite (falls back to the website if the app is not installed, with App Store link).
- `couplesapp://unlock`, `couplesapp://request/<id>`, `couplesapp://challenge/<id>`.
- The website hosts `/.well-known/apple-app-site-association`.

## 11. Purchases

RevenueCat with StoreKit 2. Products: `premium_yearly` (auto-renewing, 14-day free trial introductory offer), `premium_lifetime` (non-consumable). Restore purchases in Settings and the paywall. The app reads pair premium from our backend; RevenueCat's local entitlement is used only as a fast hint for the payer.

## 12. Accessibility and localization

- Dynamic Type up to accessibility sizes; layouts reflow.
- VoiceOver labels on every control, rings described as text ("1 hour 20 minutes of protected time left").
- Minimum touch target 44 pt; contrast per the design system.
- All strings in String Catalogs; English at launch.

## 13. App Store requirements checklist

- Privacy manifest (`PrivacyInfo.xcprivacy`) for the app and extensions.
- App Privacy answers matching `04-architecture.md` §5.
- In-app account deletion.
- Sign in with Apple.
- Review notes and demo accounts (see `07-testing-plan.md` §7).
- Age rating questionnaire answered for PG content.
