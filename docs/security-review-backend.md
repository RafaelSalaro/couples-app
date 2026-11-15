# Backend security review

**Date:** 2026-11-15 · **Reviewer:** Claude (Opus; the founder chose not to wait for Fable) · **Code reviewed:** `main` after WP-4, WP-12 (backend) and WP-14

## Scope and method

Everything the backend exposes or trusts:

- **Database:** every table's grants and Row Level Security policies, column-level privileges, every function clients can execute, every `security definer` function and its `search_path`, the realtime broadcast trigger, the pg_cron jobs.
- **Edge Functions:** authentication (JWT, shared secrets), input validation, error handling, CORS, rate limits, the webhook, the outbox sender, the public endpoints.
- **Supabase Auth settings** in `supabase/config.toml`, and secrets in the repository.
- **Abuse paths:** guessing codes and tokens, bypassing the partner, farming minutes, spamming notifications or email.

The review worked from the live local database, not the migration text (catalogue queries for grants, policies and function privileges). Each suspected problem was reproduced before it was fixed, and each fix has a regression test. The app's own client calls were replayed against the local REST API with a real user token, before and after the fixes.

## Summary

| # | Finding | Severity | Status |
|---|---|---|---|
| F1 | Four of the app's direct database calls fail in production (403): registering a push token, saving settings, reporting that protected time is off, reading unlock requests | High (core features broken: no push would ever arrive) | Fixed |
| F2 | Invite codes could be guessed without limit, to pair with a stranger | Medium | Fixed |
| F3 | Accounts could be created for an email address without proving ownership (password sign-up with confirmations off) | Medium | Fixed (local config; must match in production) |
| F4 | The partner was never told when protected time goes off (spec §11), and the day did not break the streak at once | Medium (functional, trust) | Fixed |
| F5 | The waitlist's per-IP rate limit used a client-supplied header | Low | Fixed |
| F6 | Magic links valid for an hour and re-sendable every second | Low | Fixed (local config; must match in production) |
| F7 | Five public or secret-checked functions relied on remembering `--no-verify-jwt` at deploy | Low | Fixed (`config.toml`) |
| F8 | Kudos could reference another pair's private challenge | Low | Fixed |
| F9 | Schedule proposals had no size limit (stored and pushed) | Low | Fixed |
| F10 | Rate-limit windows were never removed | Low | Fixed |
| F11 | The anonymous role could execute the RLS helpers and some trigger functions | Informational | Fixed |

Nothing found allows reading another person's data, changing anyone's minutes, or calling the minutes engine from a client. Those protections were already in place and are now covered by tests.

## What is solid (verified, not changed)

- **No client can call the engine.** No `api_*` or minutes function is executable by `anon` or `authenticated`; only the service role (Edge Functions) can. Tested (`security_test.sql`).
- **Every `security definer` function pins `search_path = ''`**, and no function in `public` lacks a fixed `search_path`.
- **RLS is on for every table.** Clients read only their own rows and their current partner's. A former partner loses access at unpair (`is_partner`/`is_pair_member` check `left_at is null`). The anonymous role reads nothing.
- **Secrets are stored as hashes:** invite code and link token, accountability code, email approve token and waitlist confirm token, all SHA-256. Tokens carry 256 bits of randomness; the 6-digit accountability code has 5 attempts and expires with the request after 5 minutes.
- **The ledger is immutable**, even for the service role; only account deletion removes the owner's own rows.
- **Edge Functions take the caller from the JWT**, verified with Supabase Auth, never from the body. Database errors are logged, not returned. The webhook and cron secrets are compared in constant time and refuse when unset. Webhook events are applied once each, and older events never override newer ones.
- **Email content is HTML-escaped.** Resend is called through its JSON API, so there is no header injection.
- **No secrets are committed.** `.p8` keys, `*.xcconfig.local` and `.env` files are ignored; the only key-like text in the repository is generated at test time.

## Findings

### F1. Four of the app's database calls fail in production — High, fixed

The iPhone app writes a few things directly, as doc 05 intends. Replaying its exact calls against the local REST API with a user token:

| App call | Before | Cause |
|---|---|---|
| Register push token (upsert on `user_id,token`) | 403 | The upsert updates `user_id` on conflict; clients could not update that column |
| Save settings (upsert on `user_id`) | 403 | An upsert needs INSERT; clients may only update their row |
| Report protected time off (`profiles.protected_time_off_since`) | 403 | Column not writable by clients |
| Read unlock requests (`select *`) | 403 | The hash columns were hidden with column-level grants, and PostgREST's `*` asks for every column |

Without the first, no push notification would ever reach anyone. Without the last, a partner's request would not show in the app. None of this had shown up because the app has only run on the in-memory backend.

**Fix** (`20261115200000_security_review.sql` and `SupabaseBackend.swift`):

- The accountability-code and approve-token hashes moved to a new server-only table, `unlock_request_secrets` (no client grant, RLS on), and members may read the whole request row.
- Clients may update `push_tokens.user_id`; the policy's `WITH CHECK` still pins it to themselves.
- Clients may update `profiles.protected_time_off_since` (see F4).
- The app updates its settings row instead of upserting; the row is created with the account. The app no longer tries to insert a missing profile.

**Verified:** every call returns 2xx after the fixes, and `unlock_request_secrets` returns 403 to clients. Regression tests in `security_review_test.sql` (R1, R4).

### F2. Invite codes could be guessed without limit — Medium, fixed

`accept_invite` checked a 6-character code (31 symbols, about 887 million codes) with no limit on attempts. With many invites open at once (each valid 72 hours), a script could try codes until one matched and pair with a stranger, who would then see that person's minutes and requests until they unpaired.

**Fix:** 10 attempts per person per hour (`take_rate_limit`). Failed attempts are returned rather than raised, so the count is not rolled back with the transaction. Link tokens (256-bit) are unaffected in practice.

**Verified:** the 10th try is checked, the 11th is refused with `rate_limited` before the code is looked at, and the next hour works again (R2).

### F3. Accounts for an email address nobody proved — Medium, fixed in config

With `enable_confirmations = false`, Supabase's password sign-up created a signed-in account for any email address. The app never uses passwords, but the endpoint exists, so someone could register under another person's address and pair under their name.

**Fix:** `enable_confirmations = true`, which magic links satisfy by themselves; minimum password length 12 as defense in depth.

**Verified:** a password sign-up now returns no session and no confirmed address.

**Production:** the same must be set in the Supabase dashboard (Authentication → Providers → Email: confirm email on). Disabling password sign-in entirely, if the plan allows, is better still.

### F4. The partner was not told when protected time goes off — Medium, fixed

Spec §11 sends the partner a neutral note when protected time is turned off, and §9 counts that day as breaking the shared streak. The app reported the status (or would have, see F1), but nothing on the server reacted. The value was also whatever time the phone sent.

**Fix:** a trigger on `profiles.protected_time_off_since`:
- it stamps the server's own time when protected time goes off;
- it ignores repeated reports that change nothing;
- it queues `protected_time_off` / `protected_time_on` for the partner;
- it marks the day as breaking the streak.

**Verified:** R3 (back-dated value replaced, note queued both ways, streak day marked, other profile columns still closed).

### F5. Waitlist rate limit used a client-supplied IP — Low, fixed

`waitlist_join` keyed its 10-per-hour limit on the *first* `X-Forwarded-For` entry, which the client controls. It now uses the last entry, added by the platform's proxy. Separately, each address gets at most one confirmation email an hour, whatever the IP.

**Note:** this assumes one trusted proxy in front of the function. Check the header shape once deployed, and use `cf-connecting-ip` or Supabase's documented client-IP header if it differs.

### F6. Magic link lifetime and resend rate — Low, fixed in config

Links were valid for 60 minutes and could be re-sent every second. They are now valid for 15 minutes, with at most one per address per minute. The same must be set in the dashboard.

### F7. JWT verification at deploy — Low, fixed

`revenuecat_webhook`, `send_notifications`, `waitlist_join`, `waitlist_confirm` and `respond_unlock_by_token` must be deployed without Supabase's JWT check (they are public or verify their own secret); every other function needs it. That relied on deploy flags. `config.toml` now declares the five, so a plain `supabase functions deploy` is correct.

### F8–F11. Smaller hardening — fixed

- **F8:** a trigger refuses kudos that reference a challenge outside the pair (a preset or the pair's own only).
- **F9:** schedule change proposals are limited to 2 KB.
- **F10:** a daily job removes rate-limit windows older than a day.
- **F11:** the RLS helpers are executable by signed-in users only, and trigger functions by no client role.

## Accepted risks (not changed; decide before or after launch)

| Risk | Why it is accepted for now |
|---|---|
| **Realtime uses public broadcast channels** (`pair:<pair_id>`). Anyone who knows a pair's id could listen for "something changed" or send fake ones. | Messages carry only a table name and a row id; the app re-reads through RLS, so a fake message causes a harmless refresh. Pair ids are known only to members. Private channels with `realtime.messages` policies are the upgrade (E15). |
| **A push token moves to whoever registers it last** (`claim_push_token`). Someone who knew another device's token could take its notifications. | Device tokens are not exposed anywhere in the app or API; this matches how APNs tokens are normally handled. |
| **Clients can insert unlimited `events`** (2 KB each). | Own rows only, no reads. A per-user rate limit is cheap to add if abuse appears. |
| **Changing one's own time zone moves "today"**, so the daily maximum and the kudos cap reset at a different hour. | The daily maximum is the person's own setting, and they can raise it anyway. Kudos inflation is limited to 30 per gift. A cooldown on time-zone changes is possible. |
| **An emergency borrow's debt is forgiven by unpairing**, and re-pairing grants starting minutes again. | Needs both partners to cooperate (a new invite and acceptance) and costs the streak. A product question rather than a security one. |
| **Offline QR unlocks are taken on the phone's word**: the server checks only that counters are unique and match the time. | The unlock happens on the phone, which the person controls anyway; the server record is history, not authority. Verifying the TOTP code on sync would need the phone to send it. |
| **Account deletion removes data first, then the auth user.** If the second step fails, the person can sign in to an account with no profile. | Rare. Retrying `delete_account` completes it. Deleting the auth user inside the same request through a database call is the cleaner fix. |
| **The 6-digit code's hash is unsalted.** | It is now readable only by the service role, lives at most 5 minutes, and allows 5 attempts. Anyone with the database already has more than that code. |
| **The QR secret is readable by both partners** (E14). | By design: both phones need it to show and check codes. |

## Production checklist (outside the repository)

1. Supabase dashboard → Authentication: confirm email on; magic link expiry 15 minutes; email rate limit as in `config.toml`; site URL the real domain; redirect URLs the real domain and `<scheme>://login-callback` only; Apple provider configured; custom SMTP (Resend) so auth emails are not capped by the default sender.
2. Secrets: set every value in `supabase/README.md` (the APNs `.p8` contents, Resend, RevenueCat webhook value, `CRON_SECRET`). Rotate any that were shared in chat or email.
3. Vault: `functions_url` and `cron_secret` for the scheduled sender.
4. Deploy functions with `config.toml` (F7), and confirm the five public functions answer without a JWT and every other function refuses without one.
5. Check the `X-Forwarded-For` shape on the deployed `waitlist_join` (F5).
6. Enable Point-in-Time Recovery or daily backups before real users.

## Tests

- `supabase/tests/security_review_test.sql`: 16 regression tests for F1–F4, F8 and F11.
- `supabase/tests/security_test.sql`: privileges and RLS (13).
- All 185 pgTAP assertions, the concurrency script and the 28 Deno tests (including 2 integration tests with real JWTs) pass after the fixes.
- The app's client calls were replayed against the REST API before (4 × 403) and after (all 2xx).

## Not covered

- The iPhone app's own security (Keychain use, Sign in with Apple nonce handling, universal-link handling) and the website. They deserve their own pass.
- Load and denial-of-service testing beyond the rate limits named here.
- A deployed Supabase project: everything was verified on the local stack, which runs the same Postgres, Auth and PostgREST but not the production network edge.
