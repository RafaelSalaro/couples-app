# 13 — Risks and open questions

## Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | LLC, D-U-N-S and Apple organization verification take weeks, delaying on-device Screen Time testing and TestFlight | High | High | Start today; build everything behind `BlockingService` with the mock; if the account is not active by the end of the sprint, consider enrolling as an individual for development only and moving to the organization account before release (would require re-requesting the entitlement under the new team) |
| R2 | Family Controls (Distribution) approval delayed or questioned | Medium | High | Request all 5 bundle IDs at once with a clear wellbeing justification; no analytics on Screen Time data; respond quickly to Apple |
| R3 | Apple Screen Time API bugs on specific iOS versions (extensions not launching, schedules not firing) | Medium | High | Device test matrix on iOS 17 and latest; keep schedules simple; monitor Apple developer forums; fallback split schedules |
| R4 | 15-minute minimum interval for Device Activity limits short unlocks | High | Low | Minimum unlock is 15 minutes by design |
| R5 | Users bypass by revoking Screen Time permission or deleting the app outside protected time | High | Medium | Deny app removal during protected time; neutral partner status; framing as a shared commitment, not enforcement |
| R6 | Perceived as a control tool, or misused in a controlling relationship | Medium | High | Safety-by-design rules (03 §16), copy review, beta survey question, safety page |
| R7 | Notification delivery delayed by Focus modes or summaries | Medium | Medium | Time-sensitive interruption level; email fallback after 2 minutes; QR works offline |
| R8 | Supabase Free tier: no backups, pausing on inactivity | Medium | High | Nightly pg_dump backups; upgrade to Pro before public launch |
| R9 | Android OEM background killing breaks blocking | High | Medium | Battery-optimization onboarding, foreground service, honest copy |
| R10 | App name conflicts (trademark) | Medium | Medium | USPTO search and attorney review before branding assets |
| R11 | Low pairing completion (one partner installs, the other never joins) | High | High | Invite flow excellence, reminders to the inviter, value before pairing, web approval page for non-installers |
| R12 | Building "complete" makes the first release large and slow to stabilize | Medium | Medium | Strict work packages, mock-first development, beta exit criteria |

## Open questions (with recommendations)

| # | Question | Recommendation | Needed by |
|---|---|---|---|
| O1 | ~~Minimum user age~~ | **Resolved 2026-11-13: 18+ in the terms; App Store age rating 12+** | — |
| O2 | Does the LLC already exist? Which state? | If not, form it now; it is on the critical path | Today |
| O3 | ~~Are all three unlock methods free?~~ | **Resolved 2026-11-13: yes, all free** | — |
| O4 | ~~Prices~~ | **Resolved: $39.99/yr and $119.99 lifetime, one price for both partners**; still test willingness to pay in the beta survey | — |
| O5 | ~~Partner sees "Protected time is off"?~~ | **Resolved: yes, neutral wording** | — |
| O6 | ~~Emergency unlock rules~~ | **Resolved: 15 min, once per 7 days, borrows minutes, breaks streak**; revisit after beta | — |
| O7 | ~~Custom challenge approval~~ | **Resolved: yes, partner approves the value** | — |
| O8 | ~~Unlock lengths~~ | **Resolved: 15/30/60 free, any 15-minute step premium** | — |
| O9 | Final app name | Shortlist: Linger (trademark check pending), Our Hours, Fica; decide after USPTO search | Before App Store listing and logo |
| O10 | Domain to buy now | A neutral domain that can redirect later, or the front-runner name's domain if available | This week |
| O11 | ~~Weekly report email on by default?~~ | **Resolved 2026-11-13: off by default (push only); opt-in email** | — |
| O12 | Beta couples: who? | Friends/family first, then waitlist | Phase 5 |
