# Backend (Supabase)

Postgres schema, Row Level Security, SQL functions, Edge Functions and scheduled jobs.
Behavior is specified in `docs/03-feature-spec.md` and `docs/05-data-model-and-api.md`.

## Run locally

Docker is provided by OrbStack: `export PATH="$HOME/.orbstack/bin:$PATH"` first.

```sh
supabase start        # from the repository root; applies migrations and seeds
supabase db reset     # re-apply migrations and seeds from scratch
supabase test db      # pgTAP database tests (supabase/tests)
./scripts/db-concurrency-test.sh    # two sessions spending at once (needs the running stack)
```

Shared test helpers live in `tests/_helpers.psql` (a person, a pair, local times) and are
included by each test file with `\ir`. The rules are SQL functions named `api_<name>`, one per
Edge Function of doc 05 §3; see the header of each migration for the conventions.

## Layout

| Path | What |
|---|---|
| `migrations/` | One file per change, never edited after it is on `main` |
| `seeds/*.sql` | Loaded in name order after migrations (`config.toml` → `[db.seed]`) |
| `tests/` | pgTAP tests |
| `functions/` | Edge Functions (Deno) |

## Edge Functions

One folder per function of doc 05 §3. The signed-in ones are thin wrappers (`_shared/api.ts`)
around the SQL function `api_<name>`, which holds the rules (E14). Public ones: `waitlist_join`,
`waitlist_confirm`, `respond_unlock_by_token`; system ones: `revenuecat_webhook`,
`send_notifications` (the outbox sender, called by pg_cron).

```sh
./scripts/functions-test.sh   # Deno unit tests, plus integration tests when the local stack runs
supabase functions serve      # run them locally on http://127.0.0.1:54321/functions/v1/<name>
```

Secrets (`supabase secrets set NAME=value`):

| Secret | For |
|---|---|
| `APP_NAME`, `APP_DOMAIN`, `APP_URL_SCHEME` | Copy and links (never hard-code the name) |
| `ALLOWED_ORIGINS` | Website origins allowed by CORS (default: `https://APP_DOMAIN`) |
| `APNS_KEY`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` | Push (.p8 key contents, key id, team id, bundle id) |
| `RESEND_API_KEY`, `EMAIL_FROM` | Email |
| `REVENUECAT_WEBHOOK_AUTH` | The Authorization value set in RevenueCat's webhook settings |
| `CRON_SECRET` | Shared with pg_cron so only it can call `send_notifications` |

`revenuecat_webhook`, `waitlist_join`, `waitlist_confirm`, `respond_unlock_by_token` and
`send_notifications` must be deployed with `--no-verify-jwt` (they check their own secret or
are public); every other function keeps JWT verification on.

For the sender to run every minute in a deployed project, store two Vault secrets once:
`select vault.create_secret('https://<ref>.supabase.co/functions/v1', 'functions_url');` and
`select vault.create_secret('<the CRON_SECRET value>', 'cron_secret');`. Without them the
scheduled call does nothing (as locally).

## Challenge seeds

Seed files insert **preset** challenges (rows with `pair_id` null) into `public.challenges`.

- `seeds/00_preset_challenges.sql` — the 5 free presets (backend lane).
- `seeds/10_challenge_library.sql` — the premium library (content lane).

Columns to supply:

| Column | Type | Rules |
|---|---|---|
| `relationship_type` | enum | `'romantic'` (launch set) or `'friends_family'` |
| `title` | text | 1–80 characters; unique per relationship type among presets |
| `description` | text | up to 280 characters |
| `minutes` | int | 5–60 |
| `category` | enum | `'together'`, `'kindness'`, `'offline_fun'`, `'movement'` |
| `is_shared` | boolean | `true` = both partners earn the minutes; `false` = only the person who did it |
| `tier` | enum | `'free'` or `'premium'` (the library uses `'premium'`) |

Leave every other column to its default (`id`, `pair_id` null, `created_by` null, `status` `'active'`, `created_at`).

Make the file safe to re-run by ending the insert with:

```sql
insert into public.challenges (relationship_type, title, description, minutes, category, is_shared, tier)
values
  ('romantic', 'Example title', 'Example description.', 15, 'offline_fun', true, 'premium')
on conflict (relationship_type, title) where pair_id is null do nothing;
```
