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

## Production project

Hosted on Supabase's free plan: project `couples-app` (ref `rnsqvtxyhwieeqylefgr`, US East) in
the organization "Couples App". The repository is linked (`supabase link`); the database
password is in the macOS Keychain as "Supabase couples-app database", the cron secret as
"Supabase couples-app CRON_SECRET". No key is stored in the repository.

```sh
export SUPABASE_DB_PASSWORD=$(security find-generic-password -a couples-app -s "Supabase couples-app database" -w)
supabase db push --remote --dry-run        # see what would change, then without --dry-run
supabase functions deploy                  # all functions; JWT settings come from config.toml
supabase test db --remote                  # pgTAP against production (each file rolls back)
./scripts/live-smoke.sh                    # the app's main path against the deployed functions
```

Set up on 2026-11-15: all migrations and both challenge seeds; the 27 functions; secrets
`APP_NAME`, `APP_DOMAIN` (placeholder `example.com`), `APP_URL_SCHEME`, `CRON_SECRET`.
**Not yet:** APNs, Resend and RevenueCat secrets (need those accounts), and the two Vault
secrets that switch on the scheduled sender (set them once APNs and Resend exist, or the
sender would fail every minute). The free plan pauses a project after a week without
requests (resume it in the dashboard) and has no automatic backups.

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
