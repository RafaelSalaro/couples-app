# 03 — Feature specification

This is the complete behavior of v1. It defines **what** the app does, not how it looks: layouts, navigation and visual design are open (see `06-ios-app.md` §5). Language in quotes is draft user-facing copy (final copy follows the voice rules in `10-brand-and-design-system.md`).

## 1. Glossary

| Term | Meaning |
|---|---|
| Pair | Two accounts linked together. v1 supports exactly one active pair per user |
| Protected time | The schedule during which chosen apps and websites are paused |
| Paused apps | The apps, categories and websites a user chose in Apple's picker |
| Unlock | A temporary window during protected time when a user's paused apps open |
| Minutes | The only currency. Earned through challenges and kudos, spent on unlocks |
| Challenge | An activity worth minutes, completed and confirmed between partners |
| Kudos | A partner awarding minutes unprompted ("I noticed you") |
| Streak | Consecutive days both partners kept protected time (see §9) |

## 2. Accounts and onboarding

**Sign-in:** Sign in with Apple (primary) and email magic link (needed later for Android and web). No passwords.

**New and returning users:**
- The same sign-in works for creating an account and for signing back in. Entering the email of an existing account sends a sign-in link and never shows an error; Sign in with Apple recognizes an existing account automatically.
- Under "Email me a link", a small secondary link reads "Already have an account? Sign in". It leads to the same sign-in options with returning-user wording ("Welcome back").
- Signing back in restores everything from the server (pair, minutes, challenges, streak, settings) and skips onboarding steps already completed. Only what lives on the phone is asked again if it is missing, for example on a new phone: Screen Time permission and the paused-apps selection.
- Error messages are specific and helpful (for example "That link has expired. We've sent you a new one." or "No connection. Try again when you're online."), never a generic "Something went wrong" for a case the app can identify.

**Signing out:** "Sign out" is a visible item in Settings (not hidden in a menu), with one confirmation. Signing out does not unpair. Because protected time cannot run without an account, the confirmation explains that protected time pauses on this phone until the person signs back in, and the partner sees the neutral status from P23 ("Protected time is off on Ana's phone").

**Onboarding order (iPhone):**
1. Welcome: the philosophy in one screen ("Not about control. About being here, together.").
2. Sign in.
3. Your name: if Sign in with Apple shared the person's name, use it and skip this step. Otherwise (Apple name hidden or not shared, or email sign-in, which provides no name) ask "What should we call you?" with a first-name field. The name is required because it is what the partner sees; it can be changed later in Settings → Profile.
4. Invite partner, or enter an invite code if the partner already invited you (see §3). User may continue alone; app features stay in "waiting for your partner" mode.
5. Notification permission with a clear reason: "So your partner's requests and kudos reach you."
6. Screen Time permission (Apple's individual authorization).
7. Choose paused apps in Apple's picker. Guidance screen first: "Tap Social, and add any other apps you want paused. Phone, Messages, Maps and your bank are best left out."
8. Confirm protected time (default 6 PM–9 AM, editable).
9. Starting minutes, daily maximum and emergency minutes, set together on one screen (defaults: start with 30 minutes; daily maximum 60 minutes; emergency minutes 15 per week).
10. Done: "Protected time starts at 6 PM."

**What works before the partner joins:** protected time, the schedule, emergency unlock, and the preview of challenges. Unlocks that need a partner show "Invite your partner to use this."

## 3. Pairing

- Partner A taps "Invite partner" and gets three options: share a link (opens the app or the App Store via the website domain), a 6-character code, or a QR code for in person.
- Invites expire after 72 hours and can be revoked.
- Partner B accepts; both see "You're now paired with Ana." Pairing requires both to confirm.
- Pairing creates the pair's shared QR secret (§6.1) and its challenge library.
- The relationship type is not shown anywhere in v1 (couples only); pairs are created as `romantic`. A choice appears only when the friends/family type launches.
- A user can be in only one active pair. Inviting while paired is disabled.

**Unpairing**
- Either partner can unpair at any time from Settings, with one confirmation. No approval from the other.
- The other partner gets a gentle notification: "Ana ended your pairing." No reason requested.
- Effects: protected time stays on each phone with its current schedule (each person can change it freely now); active minutes reset to zero (history kept); open requests are cancelled; premium stays with the payer only.
- Re-pairing with a new partner starts a fresh pair.

## 4. Protected time and the schedule

- One schedule per user in v1, shared intent but stored per user. Default: every day 6:00 PM to 9:00 AM local time (crosses midnight; overnight included on purpose so middle-of-the-night scrolling is also paused).
- Premium: up to 3 schedules (for example weekdays and weekends).
- **Stricter changes apply immediately:** adding apps, extending hours, adding days.
- **Looser changes need partner approval:** removing apps, shortening hours, removing days, turning protected time off. The partner gets a request ("Ana would like protected time to start at 7 PM"); approve or "Let's talk". Pending changes expire after 24 hours.
- If unpaired, all changes apply immediately.
- During protected time, Apple's "remove app" protection is turned on so the app cannot be deleted mid-session (ManagedSettings deny app removal).
- Apple's Screen Time permission can still be revoked by the user in iOS Settings. If that happens, the app shows the partner a neutral status "Protected time is off on Ana's phone" (see open question O5 on whether this is shown by default).

## 5. The pause screen (shield)

When a paused app opens during protected time, Apple shows our custom pause screen:

- Styled in brand colors (Apple fixes the layout). Title: "Protected time". Subtitle: time remaining ("2h 14m left") and an inviting line rotated from a list ("Want to do something together?", "Ana is around — say hi?").
- Primary button: "Ask Ana". Secondary: "Not now".
- Because Apple does not allow the pause screen to open the app, "Ask Ana" posts a time-sensitive local notification "Tap to ask Ana or use your minutes"; tapping it opens the unlock sheet. "Not now" closes the app.

## 6. Unlock methods

Every unlock: the user picks a length (15, 30 or 60 minutes; default 30; free-form in 15-minute steps for premium). Paused apps open immediately for that window, then protected time resumes automatically. A Live Activity and widget show the countdown. Unlocking again while unlocked extends the current window.

**Ending an unlock early:** the user can end any unlock before its time is up, with a short confirmation that says what happens to the unused time. Unused time is never silently lost: minutes unlocks refund the unused whole minutes to the balance (they keep their original expiry), emergency time stays available (§6.4), and free unlocks (QR, partner approval) simply end.

### 6.1 In-person QR (works offline)
- The partner opens "Show my code". Their phone shows a QR code that changes every 30 seconds (time-based one-time code from a secret shared at pairing, stored in each phone's Keychain).
- The requester scans it in the app. The code is verified on the phone, offline. A used code cannot be reused.
- Cost: free; no minutes spent. Limit: none (being together in person is the point).
- The unlock is logged locally and synced to the server when online.

### 6.2 Ask your partner (accountability code)
- Requester taps "Ask Ana", chooses a length, optionally adds a reason ("Need Instagram to reply to a client").
- Server creates the request, valid 5 minutes, and sends the partner an actionable push: "Ana asks for 30 minutes · 'Reply to a client'" with buttons **Go for it** and **Let's wait**.
- Go for it: the unlock starts on the requester's phone within seconds (server push to the requester). No minutes spent.
- Let's wait: requester sees "Ana says let's wait — maybe later?" No shaming copy.
- **Email fallback:** if the partner has notifications off, or has not responded after 2 minutes, the partner gets an email with an Approve link and a 6-digit one-time **accountability code**. The partner can share the code in person or by any message; the requester types it in to unlock. Codes expire with the request.
- If nobody answers in 5 minutes, the request expires: "No answer this time. You can try again or use your minutes."
- Limit: 3 open requests per hour to avoid notification spam.

### 6.3 Earned minutes
- Requester picks a length; minutes are spent from their balance (soonest-to-expire first). Unlock starts immediately.
- Blocked if the balance is too low or the daily maximum would be exceeded.

### 6.4 Emergency unlock
- Always available, partner or not, even with zero minutes.
- **A weekly emergency allowance per rolling 7 days** (the 7 days start at the first emergency use). Each person chooses their own allowance, next to their daily maximum (onboarding step 9 and Settings): 15, 30, 45 or 60 minutes, default 15. It can never be turned off (an emergency unlock is always available). A change applies right away: what is left this week is the new allowance minus what was already used. The allowance can be used in one session or split across several; each session runs until the remaining allowance is used up or the person ends it.
- **Only time actually used is borrowed:** the balance goes negative by the minutes used (rounded up to the whole minute), not by the full 15. It must be earned back before minutes can be spent again.
- **Ending early:** a confirmation shows what remains, for example "You've used 2 of your 15 emergency minutes this week. The other 13 stay available until Friday." Ending keeps the remainder; nothing is lost.
- The unlock sheet shows the emergency minutes left this week and when the allowance renews.
- The shared streak breaks on the first emergency use of a day, not again for each session that day.
- Apple's 15-minute minimum for Device Activity monitors (decision T6) applies. If a remaining amount under 15 minutes cannot be enforced reliably on a device, record it in `13-risks-and-open-questions.md` and ask the founder before choosing a workaround.
- The partner sees a neutral note per session: "Ana used an emergency unlock." No approval needed.

## 7. Minutes economy (exact rules)

1. All minute changes are ledger entries on the server, never edits of a balance field.
2. Entry types: `earn_challenge`, `earn_kudos`, `starting_grant`, `spend_unlock`, `emergency_borrow`, `reset`, `expire`, `admin_adjust`.
3. Earned minutes carry `expires_at = earned_at + 7 days`. Starting grants and reset grants also expire after 7 days.
4. Spending consumes the earliest-expiring earned minutes first (FIFO by expiry).
5. A nightly job (and on-demand on read) writes `expire` entries for anything past `expires_at` that was not spent.
6. Negative balance: emergency borrow creates a debt. New earnings repay debt first.
7. Daily maximum (per user, set by that user): the total spent on unlocks between local midnight and midnight cannot exceed it. Default 60 minutes; range 15–240.
8. Starting balance: granted once at pairing (default 30 minutes).
9. Mutual reset: either partner proposes "Reset both balances to 30 minutes"; both must accept. Reset expires all remaining minutes and debt for both, then grants the standard amount.
10. **Expiration timeline:** the Minutes screen shows a 7-day chart of what expires when ("12 min expire Thursday · 20 min Saturday"). A push the evening before minutes expire: "15 of your minutes expire tomorrow — maybe a walk together?"
11. Partners see each other's current balance and its expiry timeline.

## 8. Challenges and kudos

**Challenge library**
- Each challenge: title, short description, minute value, category (together, solo kindness, offline fun, movement), whether it is shared (both earn) or individual.
- **Free:** 5 preset challenges with preset minutes, for example:
  - Phone-free dinner together — 20 min each (shared)
  - Walk together without phones — 20 min each (shared)
  - Make your partner laugh today — 10 min
  - Cook something together — 25 min each (shared)
  - Write your partner a note — 10 min
- **Premium:** full library (target 60+ at launch, PG content), plus custom challenges.
- **Custom challenges (premium):** creator types the title and the minute value (5–60). The partner approves the value before it becomes available ("Ana added 'Fix the bike together' for 30 minutes — sounds right?"). Partner may suggest a different value.

**Completing a challenge**
- The person who did it taps "Done". Optional photo or note.
- The partner gets a push and confirms with one tap. Minutes are granted on confirmation. Shared challenges grant both partners on one confirmation by either.
- Unconfirmed completions expire after 48 hours.

**Kudos (premium)**
- From the partner's view of a challenge (or a free-form "Kudos" button), award minutes unprompted: "You made me laugh today."
- Recipient gets a celebration: notification "Ana says you made her laugh · +10 min", and in-app a warm Glow animation with haptics.
- Free-form kudos: 5–30 minutes, capped at 60 minutes of kudos per giver per day.

## 9. Streaks

- A **shared streak** counts consecutive days on which both partners were paired and neither used an emergency unlock nor turned protected time off.
- Breaking the streak is the only "cost" in the app. Copy: "New streak starts today." Never red.
- Milestones (3, 7, 14, 30, 60, 100 days) trigger a shared celebration.

## 10. Reports

**Live:** home screen shows both balances, today's protected time, current streak, and recent activity. Tapping the protected-time status or its time opens the protected-time schedule, where it can be managed.

**Weekly report (Sunday evening, push and in-app; email optional):**
- Individual, side by side: minutes earned, spent, expired; challenges completed; requests sent, approved; kudos given and received.
- Combined: total minutes earned together, shared challenges done, total protected hours, joint streak.
- Highlights: "Most generous: Ana gave 4 kudos this week."
- **Free:** current week only, summary numbers. **Premium:** full history, charts, highlights.
- **Private, on your own phone only:** Apple's Screen Time usage for your paused apps (shown through Apple's report extension; never sent to the server or the partner).

## 11. Notifications

| Event | Recipient | Channel |
|---|---|---|
| Unlock request | Partner | Actionable push; email fallback after 2 min or if push is off |
| Request approved / "let's wait" / expired | Requester | Push |
| Challenge marked done | Partner | Push |
| Kudos received | Recipient | Push |
| Schedule loosening request | Partner | Push |
| Minutes expiring tomorrow | Owner | Push (evening) |
| Weekly report ready | Both | Push |
| Emergency unlock used, unpaired, protected time off | Partner | Push (neutral copy) |

Users can mute each category except unlock requests and schedule requests. Quiet hours do not apply because requests are time-sensitive by nature.

## 12. Free versus premium

| Feature | Free | Premium |
|---|---|---|
| Pairing, protected time, default schedule | Yes | Yes |
| Schedules | 1 | Up to 3 |
| QR unlock, ask-your-partner, emergency unlock | Yes | Yes |
| Earned minutes | Yes | Yes |
| Challenges | 5 preset | Full library + custom |
| Kudos | No | Yes |
| Reports | This week, summary | Full history, charts, highlights |
| Widgets and Live Activity | Yes | Yes |
| Unlock lengths | 15/30/60 | Any, in 15-minute steps |

- **Prices: $39.99 per year or $119.99 lifetime, one price for the couple.** One subscription covers both partners. The paywall headline must say so ("One price for both of you"), and the price line reads "$39.99/year for both of you". Trial: 14 days, starts when the first partner opts in.
- On downgrade: earned minutes are kept; custom challenges and extra schedules are hidden, not deleted, and return on resubscribe.
- Changing the covered partner: at most once per 30 days.

## 13. Settings

Profile (name, prefilled from Sign in with Apple or the onboarding name step, editable; photo), partner and unpair, schedules, paused apps, daily maximum and emergency minutes (side by side), notification categories, subscription, export my data, delete account, privacy policy, terms, support, sign out (visible, see §2).

## 14. Account deletion

In-app, two steps. Deletes the account, unpairs, removes all personal data within 30 days (backups roll off), cancels nothing at Apple (the user is told how to cancel the Apple subscription). Required by App Store guidelines.

## 15. Offline behavior

- Protected time and unlock windows run on the phone without network (Apple enforces them).
- QR unlock works fully offline.
- Ask-your-partner and minute spending need network; the app explains when offline.
- Pending local events sync when back online.

## 16. Safety by design

Because blocking apps can be misused in controlling relationships, v1 includes:
- Identical powers for both partners; no admin role.
- Instant, unilateral unpairing.
- No location, no app list sharing, no content visibility.
- Emergency unlock always available.
- A "Support" page with relationship-safety resources linked from Settings.
