# 08 — Android app

**Timing:** built after the iPhone app is excellent — start once the iPhone beta is stable, target release within roughly 2–3 months of the iPhone launch. Mixed iPhone/Android couples are a core audience, so the interim plan below matters.

## 1. Interim support for Android partners (before the Android app)

An Android partner can already participate through email and a small web page on the website:
- Receive unlock requests by email with Approve / Let's wait buttons (signed one-time links) and the accountability code.
- Give kudos and confirm challenges from a lightweight web view (magic-link sign-in).
- They have no protected time on their own phone yet. Marketing copy must be honest about this.

## 2. Stack

- Kotlin, Jetpack Compose, Material 3 themed with our design tokens (not default Material look), minimum Android 10 (API 29), target the latest API level required by Google Play.
- Supabase Kotlin client, RevenueCat Android SDK (Google Play Billing), Firebase Cloud Messaging for push only (free), Resend for email (shared backend).
- Same backend, same Edge Functions, same data model. No backend changes expected except push via FCM in the notification sender.

## 3. How blocking works on Android (no AccessibilityService)

| Need | API | Notes |
|---|---|---|
| Detect the app in front | `UsageStatsManager.queryEvents` polled ~1 s by a foreground service | User grants Usage Access in Settings; plan an onboarding screen for it |
| Show the pause screen | Translucent single-instance Activity launched over the blocked app (our own UI, not an overlay window where avoidable) | Guard against duplicate launches and flicker |
| Keep running | Foreground service, type `specialUse` with a written justification | Persistent notification required ("Protected time is on") |
| Block websites | Local `VpnService` that refuses DNS for chosen domains (no traffic leaves the phone) | Requires VPN disclosure; Play policy declaration |
| Schedules | `AlarmManager` exact alarms + WorkManager safety net | Request exact-alarm permission where required |
| Prevent uninstall during protected time | Not available without device admin; do not attempt | Rely on partner-visible status instead |
| App list | `PackageManager` query with `QUERY_ALL_PACKAGES` justification, or `<queries>` for launcher apps | Prefer launcher-intent queries to avoid the restricted permission |

**Never use AccessibilityService** (Google Play restricts it to accessibility tools; reviewers reject blockers that could use narrower APIs).

**Known Android limitations to communicate honestly:** ~1-second delay before the pause screen appears; some manufacturers (Samsung, Xiaomi, OnePlus) kill background services — onboarding must guide users through battery optimization exemptions; a user can revoke Usage Access at any time (same neutral partner status as iOS).

## 4. Parity matrix

| Feature | iPhone v1 | Android v1 |
|---|---|---|
| Protected time, schedules | Yes | Yes |
| Website blocking | Yes (Screen Time web domains) | Yes (local VPN) |
| Pause screen | Apple shield | Our Activity |
| QR, ask partner, minutes, emergency | Yes | Yes |
| Challenges, kudos, reports | Yes | Yes |
| Private usage report | Apple report extension | UsageStats, on device only |
| Widgets | WidgetKit + Live Activity | Glance widgets + ongoing notification countdown |
| Deny uninstall during protected time | Yes | No |

## 5. Google Play publishing

- Organization developer account under the LLC (D-U-N-S number), $25 one-time. Organization accounts are exempt from the 12-testers-for-14-days rule for new personal accounts.
- Declarations: foreground service `specialUse`, VPN service use, Usage Access rationale, data safety form.
- Internal testing track → closed testing with beta couples → production.

## 6. Testing

Same database and function tests (shared). Android unit tests (JUnit), Compose UI tests, and a device matrix: Pixel (stock), Samsung (One UI), one Xiaomi or OnePlus, Android 10 and latest. Manual scripts mirror iOS §4, adding battery-optimization and reboot scenarios.
