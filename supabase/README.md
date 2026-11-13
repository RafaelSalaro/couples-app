# Backend (Supabase)

Postgres schema, Row Level Security, SQL functions, Edge Functions and scheduled jobs.
Behavior is specified in `docs/03-feature-spec.md` and `docs/05-data-model-and-api.md`.

## Run locally

Docker is provided by OrbStack: `export PATH="$HOME/.orbstack/bin:$PATH"` first.

```sh
supabase start        # from the repository root; applies migrations and seeds
supabase db reset     # re-apply migrations and seeds from scratch
supabase test db      # pgTAP database tests (supabase/tests)
```

## Layout

| Path | What |
|---|---|
| `migrations/` | One file per change, never edited after it is on `main` |
| `seeds/*.sql` | Loaded in name order after migrations (`config.toml` → `[db.seed]`) |
| `tests/` | pgTAP tests |
| `functions/` | Edge Functions (Deno) |

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
