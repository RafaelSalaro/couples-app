-- WP-3: tables, enums, indexes (docs/05-data-model-and-api.md §1).
-- All timestamps are timestamptz in UTC. All IDs are uuid.
-- Row Level Security is enabled on every table here; policies live in the next migration.

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type public.relationship_type as enum ('romantic', 'friends_family');
create type public.pair_status as enum ('active', 'ended');
create type public.change_request_status as enum ('pending', 'approved', 'declined', 'expired');
create type public.ledger_type as enum (
  'starting_grant', 'earn_challenge', 'earn_kudos', 'spend_unlock',
  'emergency_borrow', 'debt_repay', 'reset', 'expire', 'admin_adjust');
create type public.reset_status as enum ('pending', 'accepted', 'declined', 'expired');
create type public.unlock_request_status as enum (
  'pending', 'approved', 'declined', 'expired', 'cancelled', 'redeemed');
create type public.unlock_method as enum (
  'qr', 'partner_approval', 'accountability_code', 'minutes', 'emergency');
create type public.challenge_category as enum ('together', 'kindness', 'offline_fun', 'movement');
create type public.challenge_tier as enum ('free', 'premium');
create type public.challenge_status as enum ('active', 'pending_value_approval', 'archived');
create type public.completion_status as enum ('awaiting_confirmation', 'confirmed', 'expired');
create type public.streak_break_reason as enum ('emergency', 'protected_time_off', 'unpaired');
create type public.entitlement_kind as enum ('trial', 'subscription', 'lifetime');
create type public.store as enum ('app_store', 'play_store');
create type public.push_platform as enum ('ios', 'android');
create type public.push_environment as enum ('sandbox', 'production');
create type public.outbox_channel as enum ('push', 'email');
create type public.outbox_status as enum ('queued', 'sent', 'failed');

-- ---------------------------------------------------------------------------
-- Identity and pairing
-- ---------------------------------------------------------------------------

-- One per user; id equals auth.users.id. There is deliberately no foreign key to
-- auth.users: on account deletion the row is anonymized and kept (deleted_at set) so the
-- former partner's history still has something to point at, while the auth user is removed.
create table public.profiles (
  id uuid primary key,
  display_name text check (char_length(display_name) <= 60),
  photo_path text check (char_length(photo_path) <= 300),
  time_zone text not null default 'UTC',
  locale text not null default 'en' check (char_length(locale) <= 35),
  -- Set while protected time is off on this user's phone (for example Screen Time
  -- permission revoked). The partner sees a neutral status (decision P23).
  protected_time_off_since timestamptz,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.pairs (
  id uuid primary key default gen_random_uuid(),
  relationship_type public.relationship_type not null default 'romantic',
  status public.pair_status not null default 'active',
  standard_reset_minutes int not null default 30 check (standard_reset_minutes between 0 and 60),
  qr_secret_version int not null default 1,
  -- The 14-day trial counts once per pair: the first member whose trial covered the pair.
  trial_user_id uuid references public.profiles (id) on delete set null,
  trial_started_at timestamptz,
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_by uuid references public.profiles (id) on delete set null
);

-- Designed for groups later; v1 enforces exactly two active members in accept_invite.
create table public.pair_members (
  pair_id uuid not null references public.pairs (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (pair_id, user_id)
);
create unique index pair_members_one_active_pair on public.pair_members (user_id) where left_at is null;

-- The pair's shared QR secret (160-bit, base32). Server-side only: no client policy.
create table public.pair_secrets (
  pair_id uuid primary key references public.pairs (id) on delete cascade,
  secret text not null,
  version int not null default 1,
  updated_at timestamptz not null default now()
);

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references public.profiles (id) on delete cascade,
  code_hash text not null,
  link_token_hash text not null,
  expires_at timestamptz not null,
  accepted_by uuid references public.profiles (id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index invites_code_hash on public.invites (code_hash);
create unique index invites_link_token_hash on public.invites (link_token_hash);
create index invites_inviter on public.invites (inviter_id);

-- ---------------------------------------------------------------------------
-- Settings and schedules
-- ---------------------------------------------------------------------------
create table public.user_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  daily_max_minutes int not null default 60 check (daily_max_minutes between 15 and 240),
  -- TODO(product): the allowed range for the starting balance is not in the docs.
  -- 0..60 is a placeholder bound so the value cannot be abused; see the WP-3 report.
  starting_minutes int not null default 30 check (starting_minutes between 0 and 60),
  -- Keys are notification categories (see supabase/README.md). A category is on unless
  -- its value is false, except weekly_report_email which is on only when true (P24).
  notification_prefs jsonb not null default '{}'::jsonb
    check (jsonb_typeof(notification_prefs) = 'object' and pg_column_size(notification_prefs) <= 2048),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  name text not null default '' check (char_length(name) <= 40),
  -- 1 = Monday .. 7 = Sunday: the days on which the window starts.
  weekdays smallint[] not null
    check (weekdays <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(weekdays) between 1 and 7),
  start_local time not null,
  -- end_local <= start_local means the window runs past midnight into the next day.
  end_local time not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index schedules_user on public.schedules (user_id);

create table public.schedule_change_requests (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.pairs (id) on delete cascade,
  requester_id uuid not null references public.profiles (id) on delete cascade,
  -- Null for changes that have no schedule row (for example pausing fewer apps).
  schedule_id uuid references public.schedules (id) on delete cascade,
  proposed jsonb not null,
  status public.change_request_status not null default 'pending',
  expires_at timestamptz not null,
  responded_by uuid references public.profiles (id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
create index schedule_change_requests_pair on public.schedule_change_requests (pair_id, status);

-- ---------------------------------------------------------------------------
-- Minutes
-- ---------------------------------------------------------------------------

-- Each credit becomes a lot that is consumed first-expiring-first.
create table public.minute_lots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  pair_id uuid references public.pairs (id) on delete set null,
  granted int not null check (granted > 0),
  remaining int not null check (remaining >= 0),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  check (remaining <= granted)
);
create index minute_lots_open on public.minute_lots (user_id, expires_at) where closed_at is null;
create index minute_lots_expiry on public.minute_lots (expires_at) where closed_at is null;

-- Immutable; the source of truth. Positive minutes = credit, negative = debit.
-- The sum of a user's rows always equals their balance.
create table public.minute_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  pair_id uuid references public.pairs (id) on delete set null,
  type public.ledger_type not null,
  minutes int not null check (minutes <> 0),
  lot_id uuid references public.minute_lots (id) on delete set null,
  source_table text,
  source_id uuid,
  -- The user's local calendar day when the entry was written (used by the daily maximum).
  local_day date not null,
  created_at timestamptz not null default now()
);
create index minute_ledger_user_created on public.minute_ledger (user_id, created_at desc);
create index minute_ledger_user_day on public.minute_ledger (user_id, local_day, type);

-- One row per user (created with the profile). Also the per-user lock for minute changes.
create table public.minute_debt (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  pair_id uuid references public.pairs (id) on delete set null,
  debt int not null default 0 check (debt >= 0)
);

create table public.reset_proposals (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.pairs (id) on delete cascade,
  proposer_id uuid not null references public.profiles (id) on delete cascade,
  -- TODO(product): allowed range not in the docs; same placeholder bound as starting minutes.
  standard_minutes int not null check (standard_minutes between 0 and 60),
  status public.reset_status not null default 'pending',
  expires_at timestamptz not null,
  responded_by uuid references public.profiles (id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
create index reset_proposals_pair on public.reset_proposals (pair_id, status);

-- ---------------------------------------------------------------------------
-- Unlocks
-- ---------------------------------------------------------------------------
create table public.unlock_requests (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.pairs (id) on delete cascade,
  requester_id uuid not null references public.profiles (id) on delete cascade,
  minutes int not null check (minutes >= 15 and minutes % 15 = 0),
  reason text check (char_length(reason) <= 140),
  status public.unlock_request_status not null default 'pending',
  expires_at timestamptz not null,
  code_hash text,
  code_attempts int not null default 0,
  -- Hash of the one-time token in the email's approve link.
  approve_token_hash text,
  push_sent_at timestamptz,
  email_sent_at timestamptz,
  responded_by uuid references public.profiles (id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
create index unlock_requests_pair on public.unlock_requests (pair_id, created_at desc);
create index unlock_requests_requester on public.unlock_requests (requester_id, created_at desc);
create index unlock_requests_pending on public.unlock_requests (expires_at) where status = 'pending';

create table public.unlocks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  pair_id uuid references public.pairs (id) on delete set null,
  method public.unlock_method not null,
  minutes int not null check (minutes >= 15 and minutes % 15 = 0),
  started_at timestamptz not null,
  ends_at timestamptz not null,
  request_id uuid unique references public.unlock_requests (id) on delete set null,
  -- Idempotency key supplied by the phone (offline sync, retries).
  client_event_id uuid unique,
  created_at timestamptz not null default now()
);
create index unlocks_user on public.unlocks (user_id, started_at desc);
create index unlocks_pair on public.unlocks (pair_id, started_at desc);

create table public.qr_redemptions (
  pair_id uuid not null references public.pairs (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  counter bigint not null,
  redeemed_at timestamptz not null,
  unlock_id uuid references public.unlocks (id) on delete set null,
  unique (pair_id, counter)
);

-- ---------------------------------------------------------------------------
-- Challenges, kudos, streaks
-- ---------------------------------------------------------------------------

-- Presets have pair_id null; custom challenges belong to a pair.
create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid references public.pairs (id) on delete cascade,
  created_by uuid references public.profiles (id) on delete set null,
  relationship_type public.relationship_type not null default 'romantic',
  title text not null check (char_length(title) between 1 and 80),
  description text not null default '' check (char_length(description) <= 280),
  minutes int not null check (minutes between 5 and 60),
  category public.challenge_category not null,
  is_shared boolean not null default false,
  tier public.challenge_tier not null default 'premium',
  status public.challenge_status not null default 'active',
  value_proposed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
-- Presets are unique by title within a relationship type, so seed files can be re-run
-- with "on conflict (relationship_type, title) where pair_id is null do nothing".
create unique index challenges_preset_title on public.challenges (relationship_type, title) where pair_id is null;
create index challenges_pair on public.challenges (pair_id) where pair_id is not null;

create table public.challenge_completions (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges (id) on delete cascade,
  pair_id uuid not null references public.pairs (id) on delete cascade,
  completed_by uuid not null references public.profiles (id) on delete cascade,
  note text check (char_length(note) <= 280),
  photo_path text check (char_length(photo_path) <= 300),
  status public.completion_status not null default 'awaiting_confirmation',
  confirmed_by uuid references public.profiles (id) on delete set null,
  confirmed_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index challenge_completions_pair on public.challenge_completions (pair_id, created_at desc);
-- One open completion per person per challenge (a double tap must not create two).
create unique index challenge_completions_one_open
  on public.challenge_completions (challenge_id, completed_by) where status = 'awaiting_confirmation';

create table public.kudos (
  id uuid primary key default gen_random_uuid(),
  pair_id uuid not null references public.pairs (id) on delete cascade,
  giver_id uuid not null references public.profiles (id) on delete cascade,
  receiver_id uuid not null references public.profiles (id) on delete cascade,
  challenge_id uuid references public.challenges (id) on delete set null,
  message text not null default '' check (char_length(message) <= 140),
  minutes int not null check (minutes between 5 and 30),
  -- The giver's local calendar day (used by the 60-minutes-per-day cap).
  local_day date not null,
  created_at timestamptz not null default now(),
  check (giver_id <> receiver_id)
);
create index kudos_pair on public.kudos (pair_id, created_at desc);
create index kudos_giver_day on public.kudos (giver_id, local_day);

create table public.streaks (
  pair_id uuid primary key references public.pairs (id) on delete cascade,
  current_length int not null default 0 check (current_length >= 0),
  best_length int not null default 0 check (best_length >= 0),
  last_counted_day date,
  started_on date
);

create table public.daily_pair_status (
  pair_id uuid not null references public.pairs (id) on delete cascade,
  day date not null,
  broke_streak boolean not null default false,
  reason public.streak_break_reason,
  primary key (pair_id, day)
);

-- ---------------------------------------------------------------------------
-- Premium
-- ---------------------------------------------------------------------------
create table public.entitlements (
  user_id uuid not null references public.profiles (id) on delete cascade,
  product_id text not null check (char_length(product_id) <= 200),
  kind public.entitlement_kind not null,
  active boolean not null,
  expires_at timestamptz,
  store public.store not null,
  -- Time of the newest RevenueCat event applied (older events are ignored).
  event_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

-- Which member's purchase covers the pair. Rows of ended pairs are kept: they are the
-- record used by the "covered partner changes at most once per 30 days" rule.
create table public.pair_coverage (
  pair_id uuid primary key references public.pairs (id) on delete cascade,
  payer_id uuid not null references public.profiles (id) on delete cascade,
  covered_since timestamptz not null,
  last_changed_at timestamptz not null
);
create index pair_coverage_payer on public.pair_coverage (payer_id, covered_since desc);

-- Processed webhook events (idempotency).
create table public.webhook_events (
  provider text not null,
  event_id text not null,
  received_at timestamptz not null default now(),
  primary key (provider, event_id)
);

-- ---------------------------------------------------------------------------
-- Messaging and analytics
-- ---------------------------------------------------------------------------
create table public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  platform public.push_platform not null,
  token text not null check (char_length(token) between 8 and 512),
  environment public.push_environment not null default 'production',
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);
create index push_tokens_token on public.push_tokens (token);

create table public.notifications_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade,
  kind text not null,
  payload jsonb not null default '{}'::jsonb,
  channel public.outbox_channel not null,
  status public.outbox_status not null default 'queued',
  attempts int not null default 0,
  send_after timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index notifications_outbox_queue on public.notifications_outbox (send_after) where status = 'queued';

create table public.weekly_reports (
  pair_id uuid not null references public.pairs (id) on delete cascade,
  week_start date not null,
  data jsonb not null,
  created_at timestamptz not null default now(),
  primary key (pair_id, week_start)
);

-- Product events. No personal content: names and small property bags only.
create table public.events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete set null,
  name text not null check (char_length(name) between 1 and 64),
  props jsonb not null default '{}'::jsonb
    check (jsonb_typeof(props) = 'object' and pg_column_size(props) <= 2048),
  created_at timestamptz not null default now()
);

create table public.waitlist (
  id uuid primary key default gen_random_uuid(),
  email text not null check (char_length(email) between 3 and 254),
  confirmed_at timestamptz,
  source text check (char_length(source) <= 80),
  confirm_token_hash text,
  last_email_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index waitlist_email on public.waitlist (lower(email));
create index waitlist_token on public.waitlist (confirm_token_hash);

-- Fixed-window counters for rate limits (invite-code attempts, waitlist sign-ups).
create table public.rate_limits (
  key text not null,
  window_start timestamptz not null,
  count int not null default 0,
  primary key (key, window_start)
);

-- ---------------------------------------------------------------------------
-- Row Level Security on every table
-- ---------------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;
