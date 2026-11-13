# 11 — Business, legal and launch

## 1. Company and accounts (critical path)

| Step | Who | Typical time | Notes |
|---|---|---|---|
| Form the LLC (if not already formed) | Founder | Days to 2 weeks (state dependent) | Registered agent, EIN from the IRS (free, online) |
| Business bank account | Founder | 1–3 days | Needed for store payouts |
| D-U-N-S number (free via Apple's lookup page) | Founder | Up to ~1–2 weeks | Legal name and address must match the LLC filing exactly |
| Website domain + company email on it | Founder | Same day | Apple verifies a company website/domain |
| Apple Developer Program, organization ($99/yr) | Founder (Account Holder) | Days to 2+ weeks verification | Apple may phone to verify authority |
| Family Controls (Distribution) request, 5 bundle IDs | Account Holder | ~4 business days to a few weeks | Blocks TestFlight Screen Time features until approved |
| App Store Connect: agreements, tax, banking | Founder | 1 day | Needed before paid products work, even in TestFlight sandbox for some flows |
| Apple Small Business Program enrollment | Founder | Days | 15% commission instead of 30% |
| Google Play Console, organization ($25 once) | Founder | Days | Same D-U-N-S; exempt from 12-tester rule |
| RevenueCat, Supabase, Resend, Cloudflare accounts | Founder | Same day | Use company email |

**Risk:** until the Apple organization account exists, nothing can run real Screen Time code on a device under the company's signing team. See `13-risks-and-open-questions.md` R1.

## 2. Pricing (decided 2026-11-13)

**Every price is one price for the couple.** One partner pays and both partners get premium. This must be stated wherever a price appears: paywall ("$39.99/year for both of you"), App Store and Google Play listings, website pricing page, launch emails. Comparisons should make the per-person value clear (about $20 per person per year).

| Plan | Price (covers both partners) | Rationale |
|---|---|---|
| Free | $0 | Pairing, protected time, all unlock methods, 5 challenges |
| Premium yearly | $39.99 per year for the couple, 14-day free trial | Matches Paired's typical price; well below Opal ($99.99) while covering two people |
| Premium lifetime | $119.99 once for the couple | ~3x yearly; server costs continue forever, so not cheaper |

Launch offer idea: first-year $29.99 for waitlist members.

## 3. Costs

**Fixed at launch:** Apple $99/yr, domain ~$15/yr, Google $25 once. Supabase $0 → $25/mo when upgraded to Pro. Claude subscription already in place.
**Variable:** store commission 15% (Small Business Program), RevenueCat 1% after $2,500/month revenue, Resend paid tier only above 3,000 emails/month.
**Break-even on fixed costs (with Supabase Pro):** about 10–12 paying pairs per year at $39.99.
**Optional:** trademark filing ($350 per class at USPTO; classes 9 and 45 recommended), trademark attorney review (~$300–800), marketing.

## 4. Legal documents

- **Privacy policy:** what is collected and not collected (`04-architecture.md` §5), purposes, processors (Supabase, Resend, RevenueCat, Apple, Cloudflare), retention, deletion, export, contact. Covers US state laws (California CCPA/CPRA) and GDPR basics if EU users can download.
- **Terms of service:** minimum age (see O1), acceptable use, subscription terms (auto-renewal, trial, refunds via the stores), no medical claims ("not a treatment for addiction"), limitation of liability, the LLC as the contracting party.
- **EU Digital Services Act trader status** in App Store Connect if distributing in the EU (the LLC's address and contact become public).
- **Trademark:** run a full USPTO clearance search on the final name (classes 9, 42, 45) before printing anything; file once chosen.
- Have a lawyer review privacy policy and terms before public launch.

## 5. Support

- Support email on the company domain, a help center on the website, in-app "Contact support" that pre-fills app version and anonymized pair ID.
- Response target: 24 hours on weekdays.
- Safety page with relationship-safety resources (for example the US National Domestic Violence Hotline) linked from Settings.

## 6. Launch plan

**Pre-launch (now → beta)**
- Waitlist landing page live within the first week; collect emails with double opt-in.
- Build in public lightly: short posts showing design and the philosophy.
- Recruit 5–10 beta couples from friends, family and the waitlist.

**Launch week**
- App Store listing: name, subtitle, keywords, 6 screenshots in brand style, preview video (15–30 s), privacy answers.
- Email the waitlist with the launch offer.
- Submit to "App Store editorial" via the App Store Connect featuring nomination form.
- Product Hunt launch; relevant communities (couples, digital wellbeing, productivity) with genuine posts.
- Reach out to couples creators and relationship therapists who talk about phones and connection.

**After launch**
- Weekly: SEO routine (`09-website-and-seo.md` §8), review metrics, read every review and reply.
- Monthly: App Store keyword update, one product improvement shipped from feedback, refresh screenshots if conversion drops.
- Android launch as a second "launch moment" for mixed couples.

## 7. Metrics to track (privacy-friendly, own `events` table)

Install → account → paired (within 7 days) → protected time started → first unlock → first challenge confirmed → first kudos → week-4 active → trial started → paid. Plus: unlock method mix, minutes expired vs spent, unpair rate, "felt controlling" survey responses.

## 8. Future roadmap (not v1)

- Friends/family relationship type with its own challenge set.
- Groups (3–6 people) syncing to one goal.
- Portuguese (Brazil) localization.
- iPad and Mac (Screen Time APIs are available there).
- Apple Watch quick approve for unlock requests.
- Health-data challenges (steps, workouts) via Apple Health and Health Connect.
