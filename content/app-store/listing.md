# App Store listing copy

Draft, 2026-11-13. Name-agnostic: `{{APP_NAME}}` stands for the final app name (decision P22), `{{COMPANY}}` for the company and `{{DOMAIN}}` for the website domain. Replace all three before pasting into App Store Connect. Character limits are Apple's; counts below were measured with the placeholder left in, so re-count after the name is chosen.

Rules this copy follows:

- Voice and vocabulary from `docs/10-brand-and-design-system.md`: "protected time", "pause", "ask your partner", never guilt.
- Every price says it covers both partners (decision M7).
- No medical claims, no invented numbers, reviews or awards.
- Adults only: 18+ in the terms, age rating 12+ (decision P25).

## Name and subtitle

| Field | Limit | Copy |
|---|---|---|
| App name | 30 | `{{APP_NAME}}` (if the name is short, consider `{{APP_NAME}}: Time Together`) |
| Subtitle, option A (recommended) | 30 | `Less scrolling. More us.` (24) |
| Subtitle, option B | 30 | `Protected time for couples` (26) |
| Subtitle, option C | 30 | `Put the phone down, together` (28) |

## Promotional text (170, can change without a new version)

> Pause the apps that pull you apart and unlock time together. Scan, ask, or earn minutes with small moments like a phone-free dinner. One price covers both of you.

(162 characters)

## Description (4,000)

3,083 characters with the placeholders left in.

```
Less scrolling. More us.

{{APP_NAME}} is for couples who want their evenings back. You agree on protected time, the apps you each choose are paused, and when you want one, you turn to each other.

It is not about control. It is about being here, together.

HOW IT WORKS

• Pair up. Invite your partner with a link, a code or a QR code.
• Choose what to pause. Each of you picks apps on your own phone, in Apple's Screen Time picker. We suggest social media.
• Set protected time. It starts at 6 PM to 9 AM every day, and you can change it.

THREE WARM WAYS TO UNLOCK

• Scan. When you are together, scan the code on your partner's phone. It changes every 30 seconds and works offline.
• Ask. Send a quick request. Your partner answers "Go for it" or "Let's wait" right from the notification.
• Earn. Cook together, take a walk, leave a note. Your partner confirms with one tap and you earn minutes to spend later.

An emergency unlock is always there if you need your apps right away.

MINUTES, CHALLENGES AND KUDOS

• Earn minutes with challenges you do together or for each other.
• Minutes last 7 days, so they get enjoyed, not saved up.
• Kudos: your partner can give you minutes just because. "You made me laugh today · +10 min."
• Keep a shared streak and get a weekly report, side by side.

EQUAL AND PRIVATE, BY DESIGN

• You both have exactly the same powers. There is no admin.
• Either of you can unpair at any time, instantly.
• Your partner never sees which apps you paused, what you do in them, your messages or your location. Neither do we.
• Your app choices and Screen Time data stay on your phone.
• No ads. No third-party analytics.

FREE

• Pairing and protected time
• All three ways to unlock, plus the emergency unlock
• Earned minutes and 5 challenges
• This week's summary report
• Widgets and a Lock Screen countdown

PREMIUM: ONE PRICE FOR BOTH OF YOU

One of you subscribes and both of you get premium.

• A full library of challenges, plus your own
• Kudos
• Full reports with history and highlights
• Up to 3 schedules
• Unlock lengths in 15-minute steps

Premium yearly is $39.99 a year for both of you, with a 14-day free trial. Premium lifetime is $119.99 once for both of you. Prices may vary by country.

GOOD TO KNOW

• {{APP_NAME}} uses Apple's Screen Time to pause the apps you choose. You give that permission yourself, on your own phone.
• Keep Phone, Messages, Maps and your bank out of your paused apps.
• {{APP_NAME}} is for adults, 18 and over.
• {{APP_NAME}} is a tool for spending time together. It is not a medical product or a treatment for any condition.

SUBSCRIPTION DETAILS

Premium yearly renews automatically each year unless you cancel at least 24 hours before the end of the current period. Payment is charged to your Apple account. You can manage or cancel your subscription in your Apple account settings. If you start a free trial, you will be charged when it ends unless you cancel before then.

Privacy policy: https://{{DOMAIN}}/privacy/
Terms of service: https://{{DOMAIN}}/terms/
Support: https://{{DOMAIN}}/support/
```

## Keywords (100 characters, comma-separated, no spaces)

Apple already indexes the app name, subtitle and category, so those words are not repeated.

Option A, brand vocabulary only (recommended to start; 95 characters):

```
couple,partner,screen time,phone free,relationship,social media,focus,habit,together,date,detox
```

Option B, adds the terms people actually search for (98 characters):

```
couple,partner,screen time,app blocker,block apps,relationship,social media,focus,habit,phone free
```

> **Founder decision needed.** The keyword field is never shown to users, and `docs/09-website-and-seo.md` §6 lists "app blocker for couples" as a target query, but the brand vocabulary says never "block". Option A keeps to the vocabulary. Option B is likely to be found more often. Pick one; review monthly against App Store Connect search terms (doc 09 §8).

## What's New (first release)

> Hello! This is the first version of {{APP_NAME}}. Pair up, set your protected time, and tell us what you think. We read every message.

## Categories and age rating

| Field | Value | Note |
|---|---|---|
| Primary category | Lifestyle | Matches the website's structured data |
| Secondary category | Health & Fitness | Alternative: Productivity. Founder to confirm |
| Age rating | 12+ | Decision P25. Answer the age-rating questionnaire truthfully; the rating Apple computes may differ, and the terms require 18+ either way |
| Price | Free, with in-app purchases | |

## URLs

| Field | Value |
|---|---|
| Support URL | `https://{{DOMAIN}}/support/` |
| Marketing URL | `https://{{DOMAIN}}/` |
| Privacy policy URL | `https://{{DOMAIN}}/privacy/` |
| Terms (EULA) | `https://{{DOMAIN}}/terms/` (add as a custom license agreement, or link in the description as above) |

## In-app purchases

Product identifiers are from `docs/06-ios-app.md` §10.

| Product ID | Type | Display name (30) | Description (45) |
|---|---|---|---|
| `premium_yearly` | Auto-renewable subscription, 14-day free trial | `Premium Yearly, for you both` (28) | `One subscription covers both partners.` (38) |
| `premium_lifetime` | Non-consumable | `Premium Lifetime, for you both` (30) | `One purchase covers both partners.` (34) |

Subscription group display name: `{{APP_NAME}} Premium`.

## Screenshots (6, in this order)

Captions are short enough to read at thumbnail size. Use the brand colors and Fraunces for captions (doc 10). Show real app screens, not mock-ups, and no people's real names other than the sample names used in the spec ("Ana").

| # | Screen | Caption | Supporting line |
|---|---|---|---|
| 1 | Home during protected time, both balances and streak | Less scrolling. More us. | Protected time for the two of you |
| 2 | The pause screen ("Protected time", "Ask Ana") | A calm pause, together | Evenings and mornings, back |
| 3 | Unlock sheet with the three methods | Three warm ways to unlock | Scan, ask or earn |
| 4 | Kudos celebration ("Ana says you made her laugh · +10 min") | "I noticed you." | Kudos: minutes just because |
| 5 | Challenge library and a shared challenge | Earn time by showing up | Dinner, a walk, a note |
| 6 | Settings or pairing screen showing identical powers and Unpair | Equal and private, always | Same powers. Unpair any time. Nothing shared but minutes |

## App preview video (15 to 30 seconds)

1. (0–4 s) Two phones side by side at 6 PM; protected time begins, the ring closes. Text: "Protected time."
2. (4–9 s) A paused app opens to the pause screen; tap "Ask Ana". Text: "Want an app? Ask each other."
3. (9–14 s) On the other phone, the notification: "Go for it". The ring opens into a countdown.
4. (14–20 s) Marking "Phone-free dinner" done, partner confirms, "+20 min each".
5. (20–26 s) Kudos celebration. Text: "Kudos, just because."
6. (26–30 s) Logo and "Less scrolling. More us."

Apple requires preview footage to be captured from the app itself.

## App Privacy answers (draft, from `docs/04-architecture.md` §5)

To be confirmed against the shipped build and the final privacy policy before submission.

- **Tracking:** No. The app does not track users and contains no third-party analytics or advertising SDKs.
- **Data linked to the user, used for App Functionality only:**
  - Contact info: email address; name (display name)
  - User content: photos (optional profile photo and optional challenge photos); other user content (challenge titles, notes, kudos messages, request reasons); customer support messages
  - Identifiers: user ID; device ID (push notification token)
  - Purchases: purchase history (premium status)
  - Usage data: product interaction (first-party product events without content), also used for Analytics
- **Not collected:** location, contacts, browsing history, search history, health and fitness, financial info, sensitive info, diagnostics sent to third parties.
- **Screen Time:** the selection of apps and all Screen Time usage data stay on the device and are not collected.

## Still needed before this can be submitted

- Final app name (and a re-count of every limited field), company name, domain.
- Screenshots and preview video from the real app.
- Attorney-reviewed privacy policy and terms live on the website.
- Founder choices marked above: keyword option, secondary category.
