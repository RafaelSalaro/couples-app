# App Review notes

Draft, 2026-11-13, for `docs/07-testing-plan.md` §7. `{{APP_NAME}}`, `{{COMPANY}}` and `{{DOMAIN}}` are placeholders. Items marked **TO DO** need the real app, real accounts or the founder; nothing here should be pasted into App Store Connect until they are filled in and the text has been checked against the build being submitted.

The first block is the text for the "Notes" field in App Store Connect (App Review Information). The rest is the checklist of what goes with it.

---

## Text for the Notes field

```
Thank you for reviewing {{APP_NAME}}.

WHAT THE APP DOES
{{APP_NAME}} is a digital wellbeing app for couples. Two adults pair their accounts and agree on "protected time" (default 6 PM to 9 AM). During protected time, the apps each person chose are paused on that person's own iPhone. They can open them again in three ways: by scanning a rotating QR code on their partner's phone, by asking their partner (push notification with "Go for it" / "Let's wait"), or by spending minutes earned through shared challenges. An emergency unlock (15 minutes, no approval) is always available.

WHY IT USES SCREEN TIME (FAMILY CONTROLS)
The app uses FamilyControls with individual authorization (AuthorizationCenter, .individual), ManagedSettings and DeviceActivity to pause the apps that the user selects for themselves in Apple's FamilyActivityPicker, on their own device, on the schedule they set. It is self-directed digital wellbeing for adults. It is not parental control and not a monitoring tool:
- Each user authorizes Screen Time on their own device and picks their own apps.
- Nobody can configure another person's device.
- Both partners have identical capabilities. There is no administrator role.
- Either partner can unpair instantly, without the other's approval (Settings > Partner > Unpair).

NO USAGE DATA LEAVES THE DEVICE
- The FamilyActivitySelection (app and category tokens) is stored only in the App Group container on the device. It is never sent to our server or to the partner.
- Screen Time usage is shown only inside the DeviceActivityReport extension, privately to the device owner. It is never transmitted.
- The partner sees only data the app itself creates: minutes balance, unlock requests, challenges, kudos and a shared streak.
- The app contains no third-party analytics or advertising SDKs and does not track users.

HOW PAUSING WORKS
- A DeviceActivity schedule starts and ends protected time. The DeviceActivityMonitor extension applies and clears shields with ManagedSettings.
- When a paused app is opened, our ShieldConfiguration extension shows a calm screen ("Protected time") with the time remaining and two buttons: "Ask <partner>" and "Not now".
- Because a shield cannot open the app, "Ask <partner>" posts a local notification; tapping it opens the unlock sheet in {{APP_NAME}}.
- During protected time the app enables "deny app removal" so the commitment is not lost by accident. It is cleared when protected time ends, and the user can revoke Screen Time access in iOS Settings at any time.

HOW TO TEST (DEMO ACCOUNTS)
Pairing needs two people, so we provide two accounts that are already paired with each other, each with a balance of minutes. Please sign in with "Continue with email" and the credentials in the Sign-In Information fields.

Account A: [TO DO: demo email A]
Account B: [TO DO: demo email B]
Sign-in: [TO DO: describe the reviewer sign-in path. Magic links need a mailbox, so provide a fixed one-time code or password path for these two accounts only]

Suggested path with one device (Account A):
1. Sign in. Allow notifications. Allow Screen Time access when iOS asks.
2. Choose one or two apps to pause (for example Safari or any installed social app).
3. Nothing to start: both demo accounts have protected time all day, every day, so it is already on.
4. Open a paused app: the "Protected time" screen appears.
5. Return to {{APP_NAME}} > Unlock > "Use my minutes" > 15 minutes. The paused app opens and a countdown appears.
6. Unlock > "Emergency unlock" shows the always-available 15-minute option.
7. Challenges: mark "Phone-free dinner together" as done. (Confirmation by the partner is step 3 below.)

With a second device (Account B), optional:
1. On B: Unlock > "Show my code". On A: Unlock > "Scan" and scan it. A's apps open (works offline).
2. On A: Unlock > "Ask <partner>". B receives a notification with "Go for it" and "Let's wait".
3. On B: confirm A's challenge; both balances increase.

The attached screen recording shows all of these flows on two devices, including the ones that need a second phone.

PURCHASES
Premium is optional. "Premium Yearly" (auto-renewing, 14-day free trial) and "Premium Lifetime" (non-consumable). One purchase covers both partners in a pair; this is stated on the paywall and in the listing. Restore Purchases is on the paywall and in Settings > Subscription. All core features, including every way to unlock and the emergency unlock, are free.

ACCOUNT DELETION
Settings > Delete account (two steps). This deletes the account and personal data and unpairs the user. Steps are also at https://{{DOMAIN}}/support/#delete-account

SIGN IN
Sign in with Apple and email link. No passwords.

AGE AND CONTENT
The app is for adults (18+ in our terms). User-entered text (challenge titles, notes, kudos, request reasons) and optional photos are visible only to the user's one paired partner, never publicly. [TO DO: describe the in-app way to report a concern or contact support about partner content, and confirm it exists in the build.]

SAFETY
Because the app involves two people agreeing to pause apps, it is designed against coercive use: identical powers, instant one-sided unpairing, no location or content sharing, an always-available emergency unlock, and a safety resources page linked from Settings (https://{{DOMAIN}}/safety/).

CONTACT
[TO DO: reviewer contact name, phone and email]
```

---

## What goes with the notes

| Item | Status | Owner |
|---|---|---|
| Two demo accounts, already paired, each with a pre-filled minutes balance (for example 60 minutes) and one challenge awaiting confirmation | Script ready: `supabase/demo/review_accounts.sql` (60 minutes each, protected time all day, one challenge by B awaiting A). Checked on the local stack. **TO DO:** run it on the production project; a sign-in path that does not depend on a mailbox (founder question 5) | Founder |
| Sign-In Information fields in App Store Connect filled with Account A | **TO DO** | Founder |
| Screen recording, 2 to 3 minutes: pairing, protected time starting, the pause screen, each unlock method (scan, ask, minutes, emergency), a challenge confirmation and a kudos | **TO DO** on two real iPhones | Founder |
| Privacy policy URL and support URL live on the real domain | Drafts exist (`content/legal/`, website pages). **TO DO:** attorney review, real domain | Founder |
| Family Controls (Distribution) entitlement approved for all five bundle IDs | **TO DO**, needs the organization developer account (decision log T1, T2) | Account Holder |
| App Privacy answers | Draft in `content/app-store/listing.md` | Founder to confirm |
| Export compliance | The app uses only standard encryption (HTTPS, Apple CryptoKit for one-time codes) and declares `ITSAppUsesNonExemptEncryption = false` in its Info.plist. **TO DO:** founder to confirm that answer | Founder |
| Every label and path quoted in the notes checked against the submitted build | **TO DO** at submission. The labels above come from the feature spec and may differ slightly in the app | iPhone lane |

## Text for the Family Controls (Distribution) entitlement request

Use for each of the five bundle IDs (app, Monitor, ShieldConfig, ShieldAction, Report), adjusting the last sentence to the target.

```
{{APP_NAME}} is a digital wellbeing app for adult couples. Each user grants Screen Time access with individual authorization on their own device and selects, in the FamilyActivityPicker, the apps they personally want paused during a schedule they set ("protected time"). The app uses ManagedSettings to shield those apps during the schedule and DeviceActivity to start and end it and to end temporary unlock windows.

It is not a parental control or monitoring product. No user can configure or view another person's device. Both partners in a pair have identical capabilities and either can leave at any time. The selection tokens and all Screen Time usage data remain on the device: they are stored only in the app's App Group container and are never sent to our servers, to the partner or to any third party. The app contains no third-party analytics or advertising SDKs.

This target ([app / DeviceActivityMonitor extension / ShieldConfiguration extension / ShieldAction extension / DeviceActivityReport extension]) needs the entitlement to [request authorization and present the picker / apply and clear shields when the schedule or an unlock window starts and ends / draw the custom "Protected time" shield / handle the shield's buttons / show the user their own usage privately on device].
```

## Notes for whoever submits

- Reviewers cannot pair with themselves and may have only one device. The notes are written so that one device and Account A are enough to see protected time, the pause screen, a minutes unlock and the emergency unlock. The recording covers the rest.
- If protected time depends on the clock, make sure it is active during review: either give the demo accounts an all-day schedule or provide the "start now" control mentioned in step 3. Decide which before submission; do not ship a reviewer-only control that changes product behavior for everyone without recording it in the decisions log.
- Keep the tone factual. Apple's main concerns with Screen Time apps are misuse for monitoring and data leaving the device; the notes answer both directly.
