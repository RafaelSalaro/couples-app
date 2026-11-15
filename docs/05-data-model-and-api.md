# 05 — Data model and API

Postgres on Supabase. All timestamps `timestamptz` in UTC. All IDs `uuid` (`gen_random_uuid()`). Every table has Row Level Security enabled. Clients **read** their own pair's rows directly; **all writes** that affect minutes, pairs, requests, coverage or approvals go through Edge Functions.

## 1. Tables

### Identity and pairing

**profiles** — one per user (`id` = `auth.users.id`)
`id, display_name text not null (from Sign in with Apple when shared, else the onboarding name step), photo_path text null, time_zone text (IANA), locale text, created_at, deleted_at null`

**pairs**
`id, relationship_type enum('romantic','friends_family') default 'romantic', status enum('active','ended'), standard_reset_minutes int default 30, qr_secret_version int default 1, created_at, ended_at null, ended_by uuid null`

**pair_members** — designed for groups later; v1 enforces exactly 2 active members
`pair_id, user_id, joined_at, left_at null` · primary key (pair_id, user_id) · partial unique index on `user_id where left_at is null` (one active pair per user)

**invites**
`id, inviter_id, code_hash text, link_token_hash text, expires_at (72h), accepted_by null, accepted_at null, revoked_at null, created_at`

### Settings and schedules

**user_settings**
`user_id pk, daily_max_minutes int default 60 check (15..240), emergency_allowance_minutes int default 15 check (in 15, 30, 45, 60), starting_minutes int default 30, notification_prefs jsonb, created_at, updated_at`

**schedules**
`id, user_id, name text, weekdays smallint[] (1=Mon..7=Sun), start_local time, end_local time, enabled bool, created_at, updated_at` · v1 free: 1 row; premium: up to 3

**schedule_change_requests**
`id, pair_id, requester_id, schedule_id, proposed jsonb, status enum('pending','approved','declined','expired'), expires_at (24h), responded_by, responded_at, created_at`

### Minutes

**minute_ledger** — immutable; the source of truth
`id, user_id, pair_id, type enum('starting_grant','earn_challenge','earn_kudos','spend_unlock','emergency_borrow','debt_repay','reset','expire','admin_adjust'), minutes int (positive = credit, negative = debit), lot_id null, source_table text null, source_id uuid null, local_day date, created_at`

**minute_lots** — each credit becomes a lot that is consumed FIFO by expiry
`id, user_id, pair_id, granted int, remaining int check (remaining >= 0), expires_at, created_at, closed_at null`

**minute_debt** — one row per user
`user_id pk, pair_id, debt int default 0 check (debt >= 0)`

Rules implemented in SQL functions (called only by Edge Functions):
- `grant_minutes(user, pair, minutes, type, source)`: repay debt first; remainder becomes a lot expiring in 7 days; ledger rows written.
- `spend_minutes(user, pair, minutes, unlock_id)`: check debt = 0, available ≥ minutes, daily spend + minutes ≤ daily max (in the user's local day); consume lots ordered by `expires_at`; ledger rows written. Runs in a transaction with `select … for update` on the user's lots.
- `expire_minutes()`: for lots with `expires_at < now()` and `remaining > 0`, write an `expire` ledger row and close the lot. Run by pg_cron hourly.
- `balance(user)` view: `sum(remaining of open lots) - debt`.

**reset_proposals**
`id, pair_id, proposer_id, standard_minutes, status enum('pending','accepted','declined','expired'), expires_at (24h), responded_by, created_at`

### Unlocks

**unlock_requests**
`id, pair_id, requester_id, minutes int, reason text null (max 140), status enum('pending','approved','declined','expired','cancelled','redeemed'), expires_at (5 min), code_hash text null, code_attempts int default 0, push_sent_at, email_sent_at null, responded_by null, responded_at null, created_at`

**unlocks**
`id, user_id, pair_id, method enum('qr','partner_approval','accountability_code','minutes','emergency'), minutes int, started_at, ends_at, ended_early_at null, minutes_used int null, request_id null, client_event_id uuid unique (idempotency for offline sync), created_at`

Emergency allowance per user: `user_settings.emergency_allowance_minutes` per rolling 7-day window starting at the first emergency use in that window; remaining = allowance − minutes used by emergency unlocks in the window (never below zero).

**qr_redemptions**
`pair_id, user_id, counter bigint, redeemed_at` · unique (pair_id, counter)

### Challenges, kudos, streaks

**challenges** — presets have `pair_id null`
`id, pair_id null, created_by null, relationship_type, title text (max 80), description text (max 280), minutes int (5..60), category enum('together','kindness','offline_fun','movement'), is_shared bool, tier enum('free','premium'), status enum('active','pending_value_approval','archived'), value_proposed_by null, created_at`

**challenge_completions**
`id, challenge_id, pair_id, completed_by, note text null, photo_path null, status enum('awaiting_confirmation','confirmed','expired'), confirmed_by null, confirmed_at null, expires_at (48h), created_at`

**kudos**
`id, pair_id, giver_id, receiver_id, challenge_id null, message text (max 140), minutes int (5..30), created_at` · daily cap 60 minutes per giver enforced in function

**streaks**
`pair_id pk, current_length int, best_length int, last_counted_day date, started_on date`

**daily_pair_status**
`pair_id, day date, broke_streak bool, reason enum('emergency','protected_time_off','unpaired') null` · pk (pair_id, day)

### Premium

**entitlements** (from RevenueCat webhooks)
`user_id, product_id, kind enum('trial','subscription','lifetime'), active bool, expires_at null, store enum('app_store','play_store'), updated_at` · pk (user_id, product_id)

**pair_coverage**
`pair_id pk, payer_id, covered_since, last_changed_at` · a user's entitlement covers at most one pair; changing the covered pair allowed once per 30 days

**pair_premium** view: pair is premium when `pair_coverage.payer_id` is an active member with an active entitlement.

### Messaging and analytics

**push_tokens** `id, user_id, platform enum('ios','android'), token, environment enum('sandbox','production'), updated_at`
**notifications_outbox** `id, user_id, kind, payload jsonb, channel enum('push','email'), status enum('queued','sent','failed'), attempts, send_after, created_at`
**weekly_reports** `pair_id, week_start date, data jsonb, created_at` · pk (pair_id, week_start)
**events** `id, user_id null, name text, props jsonb (no personal content), created_at`
**waitlist** (website) `id, email, confirmed_at null, source text, created_at`

## 2. Row Level Security (pattern)

```sql
-- helper
create function is_pair_member(p uuid) returns boolean language sql stable as $$
  select exists (select 1 from pair_members
                 where pair_id = p and user_id = auth.uid() and left_at is null);
$$;

-- example: read-only access for members
create policy "members read" on unlock_requests for select using (is_pair_member(pair_id));
-- no insert/update/delete policies for clients: writes happen in Edge Functions with the service role
```
Exceptions where clients may write directly: `profiles` (own row), `user_settings` (own row, except values validated by check constraints), `push_tokens` (own rows), `events` (insert own).

Reads beyond the pattern (E14): current pair members may read their pair's row in `pair_secrets` (both phones need the QR secret; the inviter never calls `accept_invite`). The view `pair_premium` shows the caller's own current pair while its premium is on.

The accountability code's hash and the email approve token's hash live in `unlock_request_secrets`, which no client can read; members read the whole `unlock_requests` row (security review F1). A phone reports protected time off by writing `profiles.protected_time_off_since`; the server stamps the time, tells the partner and breaks the day's streak (F4).

Each Edge Function is a thin wrapper around one SQL function `api_<name>(p_user, …)` in the migrations, which holds the rules and is executable only by the service role (E14).

## 3. Edge Functions (HTTPS, JSON, caller's JWT required)

| Function | Input | Effect | Errors |
|---|---|---|---|
| `create_invite` | — | Returns `{code, link}`; stores hashes | already_paired |
| `accept_invite` | `{code \| link_token}` | Creates pair, members, starting grants, coverage if any, returns pair + QR secret; at most 10 tries per person per hour | invalid, expired, already_paired, rate_limited |
| `revoke_invite` | — | Cancels the caller's open invite | — |
| `unpair` | — | Ends pair, resets active minutes, cancels pending items, notifies partner | not_paired |
| `rotate_qr_secret` | — | New secret version, pushes to both | — |
| `create_unlock_request` | `{minutes, reason?}` | Request + push to partner; schedules email fallback | rate_limited, partner_missing |
| `respond_unlock_request` | `{request_id, approve}` | Approve → unlock row + push to requester; decline → push | expired, not_partner |
| `redeem_accountability_code` | `{request_id, code}` | Verifies hashed code, creates unlock | invalid, expired, too_many_attempts |
| `spend_minutes_unlock` | `{minutes, client_event_id}` | Spend FIFO, create unlock | insufficient, over_daily_max, in_debt |
| `emergency_unlock` | `{client_event_id}` | Start a session for the remaining weekly emergency allowance; note to partner; mark the day (streak) once | allowance_used_up |
| `end_unlock_early` | `{unlock_id, client_event_id}` | Ends an active unlock. Emergency: borrow only the minutes used (rounded up) and keep the rest of the allowance. Minutes: refund unused whole minutes to their original lots. QR / partner approval: end only | not_active |
| `sync_qr_unlocks` | `[{counter, minutes, started_at, client_event_id}]` | Idempotent insert of offline QR unlocks | duplicate_counter |
| `complete_challenge` | `{challenge_id, note?, photo?}` | Completion awaiting confirmation + push | premium_required |
| `confirm_completion` | `{completion_id}` | Grants minutes (both if shared) | not_partner, expired |
| `give_kudos` | `{receiver_id, minutes, message, challenge_id?}` | Grant + celebration push | premium_required, daily_cap |
| `create_custom_challenge` | `{title, description, minutes, category, is_shared}` | Pending value approval + push | premium_required |
| `respond_challenge_value` | `{challenge_id, approve, counter_minutes?}` | Activate or counter-propose | — |
| `propose_reset` / `respond_reset` | `{standard_minutes}` / `{proposal_id, accept}` | Mutual reset of both balances | — |
| `propose_schedule_change` / `respond_schedule_change` | `{schedule_id, proposed}` / `{request_id, approve}` | Looser changes need approval; stricter applied directly | — |
| `revenuecat_webhook` | RevenueCat event | Upsert entitlements, recompute coverage | bad_signature |
| `export_my_data` | — | JSON of the user's data | — |
| `delete_account` | — | Unpair, anonymize, delete auth user | — |
| `waitlist_join` (public) | `{email, source}` | Insert + double opt-in email | rate_limited |
| `waitlist_confirm` (public, GET) | `?token=` | Confirms the address, redirects to `/waitlist/confirmed/` | — |
| `respond_unlock_by_token` (public) | `{token, approve}` | The approve link in the fallback email; same as `respond_unlock_request` | invalid, expired |
| `send_notifications` (cron only) | — | Delivers the outbox: APNs and Resend | unauthorized |

All functions: idempotent where a `client_event_id` is given; return `{ok, data}` or `{ok:false, error:{code, message}}`.

## 4. Scheduled jobs (pg_cron)

| Job | Schedule | What |
|---|---|---|
| expire_minutes | hourly | Close expired lots, ledger `expire` |
| expire_requests | every minute | Pending requests past 5 min → expired; push requester |
| email_fallback | every minute | Requests pending > 2 min without email → send code email |
| expire_misc | hourly | Invites, completions (48h), proposals (24h) |
| streak_rollover | hourly | For pairs whose local day ended, count or break streak |
| expiry_reminder | hourly | At ~7 PM local, push owners whose minutes expire tomorrow |
| weekly_report | hourly on Sunday | At ~7 PM local, build `weekly_reports` row and push |

## 5. Realtime channels

`pair:<pair_id>` broadcasts changes to: balances, unlock_requests, challenge_completions, kudos, schedule_change_requests, streaks.

## 6. Migrations and seed

- Migrations in `supabase/migrations`, one per change, never edited after merge.
- Seed file with the 5 free preset challenges and the premium library (romantic set at launch; friends/family set later).
- Database tests with pgTAP for every SQL function in §1 (see `07-testing-plan.md`).
