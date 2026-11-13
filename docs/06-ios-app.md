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
- Shield Configuration: Dusk background, cream title, Glow accent; title "Protected time", subtitle with time remaining (computed from the active schedule in the App Group), primary "Ask {partner}", secondary "Not now".
- Shield Action: primary → post a time-sensitive local notification "Tap to ask {partner} or use your minutes" (deep link `couplesapp://unlock`), respond `.close`; secondary → `.close`.
- Report extension: shows the user's own usage of paused apps during protected time this week. No data leaves the extension.
- Authorization loss: on every app launch and on `scenePhase` active, check `AuthorizationCenter.shared.authorizationStatus`; if revoked, show a gentle re-enable screen and report the status to the server (partner sees neutral status, subject to open question O5).

## 5. Screens

| Area | Screens |
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

## 6. Motion and haptics (signature moments)

All animations: spring-based, 200–450 ms, eased; Reduce Motion replaces movement with cross-fades.

1. **Kudos received:** Glow-colored warmth blooms from the center, the minute count ticks up with `contentTransition(.numericText())`, a soft success haptic.
2. **Unlock approved:** the protected-time ring opens like a door and becomes a countdown ring; light haptic.
3. **QR scan success:** two circles (the brand motif) slide together and overlap; success haptic.
4. **Streak milestone:** the streak number grows with a gentle scale and a warm particle drift (short, once).
5. **Minutes expiring timeline:** bars animate in from the baseline, staggered by day.
6. **Pairing complete:** both avatars move toward each other and settle overlapped.

Never: shaking, red flashes, "denied" sounds.

## 7. Widgets and Live Activity

- Small widget: protected-time status and your balance.
- Medium widget: both balances and streak.
- Lock-screen widget: time left in protected time or unlock.
- Live Activity + Dynamic Island: unlock countdown, started on every unlock, ends automatically.

## 8. Notifications

Categories with actions:
- `UNLOCK_REQUEST`: actions "Go for it", "Let's wait" (authenticated action, calls `respond_unlock_request`).
- `COMPLETION_CONFIRM`: action "Confirm".
- `SCHEDULE_CHANGE`: "Approve", "Let's talk".
Time-sensitive interruption level for unlock requests and the shield prompt. Requires the Time Sensitive Notifications capability.

## 9. Deep links and universal links

- `https://<domain>/i/<token>` → accept invite (falls back to the website if the app is not installed, with App Store link).
- `couplesapp://unlock`, `couplesapp://request/<id>`, `couplesapp://challenge/<id>`.
- The website hosts `/.well-known/apple-app-site-association`.

## 10. Purchases

RevenueCat with StoreKit 2. Products: `premium_yearly` (auto-renewing, 14-day free trial introductory offer), `premium_lifetime` (non-consumable). Restore purchases in Settings and the paywall. The app reads pair premium from our backend; RevenueCat's local entitlement is used only as a fast hint for the payer.

## 11. Accessibility and localization

- Dynamic Type up to accessibility sizes; layouts reflow.
- VoiceOver labels on every control, rings described as text ("1 hour 20 minutes of protected time left").
- Minimum touch target 44 pt; contrast per the design system.
- All strings in String Catalogs; English at launch.

## 12. App Store requirements checklist

- Privacy manifest (`PrivacyInfo.xcprivacy`) for the app and extensions.
- App Privacy answers matching `04-architecture.md` §5.
- In-app account deletion.
- Sign in with Apple.
- Review notes and demo accounts (see `07-testing-plan.md` §7).
- Age rating questionnaire answered for PG content.
