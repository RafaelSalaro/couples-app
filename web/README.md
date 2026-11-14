# Website

Astro static site for Cloudflare Pages. See `docs/09-website-and-seo.md` and
`docs/10-brand-and-design-system.md`.

## Commands (run in `web/`)

| Command | What it does |
|---|---|
| `npm ci` | Install dependencies |
| `npm run dev` | Local dev server |
| `npm run build` | Build to `dist/`, then run the SEO and hygiene checks (`scripts/check-site.mjs`). CI runs this |
| `npm test` | Unit tests for the waitlist client |
| `npm run check` | Type check (`astro check`) plus the site checks |
| `npm run mock:waitlist` | Local test double of the `waitlist_join` function on `http://127.0.0.1:8787` |
| `CHROME_PATH=… npm run test:e2e` | Browser test of the waitlist form against the test double |
| `CHROME_PATH=… npm run lighthouse -- / /pricing/` | Lighthouse, mobile and desktop, against `dist/`; fails under 95 |

`CHROME_PATH` is any Chrome or Chromium binary. One way to get one without installing a browser:
`npx @puppeteer/browsers install chrome@stable --path ~/.cache/chrome-for-testing`.

## Configuration

Everything that is not final lives in **one file**, `src/config/site.ts`: app name, company,
domain, contact emails, prices, launch state, deep-link identifiers and the waitlist endpoint.
Each value can be overridden with an environment variable (see `.env.example`), locally in
`.env` and in Cloudflare Pages under Settings → Environment variables. Never write the name,
company or domain in a page: `npm run build` fails if it finds them outside the config.

## Waitlist

The form posts JSON `{email, source}` to the `waitlist_join` Edge Function
(`docs/05-data-model-and-api.md` §3) and expects `{ok: true, data}` or
`{ok: false, error: {code, message}}`. Set `PUBLIC_WAITLIST_ENDPOINT` to the function URL.
What the website expects from the function:

- CORS: allow `POST` and `OPTIONS` from the site origin with headers `content-type, authorization, apikey`.
- Error codes `rate_limited` (or HTTP 429) and `invalid_email`; anything else shows a generic "try again".
- Joining twice returns `ok: true` (so the form never reveals who is on the list).
- The confirmation link in the double opt-in email ends on `/waitlist/confirmed/`.
- If the function verifies JWTs, set `PUBLIC_SUPABASE_ANON_KEY`; the form then sends it as `apikey` and `Authorization`.

Without `PUBLIC_WAITLIST_ENDPOINT` the form explains that the waitlist is not open yet.
`scripts/mock-waitlist.mjs` implements the same contract in memory for local work and tests; it
sends no email and must never be deployed.

## Deep links and token routes

- `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json` are generated from
  the config (`src/pages/[...deeplink].ts`). Set `APPLE_TEAM_ID` and `IOS_BUNDLE_ID` when the Apple
  account exists. `assetlinks.json` is an empty list until the Android app has a signing key.
- `/i/<token>` (invite link fallback) is served by `/invite/` through a rewrite in `public/_redirects`.
  The page never reads or sends the token.
- `public/_headers` sets the JSON content type for the association file and no-index, no-referrer
  and no-store on token routes.

## Guides

One Markdown file per guide in `src/content/guides/` (schema in `src/content.config.ts`): title,
description, lede, published date, cluster, FAQ and optional sources. Guides must not name the app
or state prices in the body; the layout adds the call to action and the links to `/how-it-works/`
and `/pricing/`. Set `draft: true` to keep a guide out of the build. Six drafts for the weeks after launch of the
site are in the folder (`plannedWeek` 1 to 6). Publishing a draft: read it once, remove `draft`
and `plannedWeek`, set `published` to the day it goes live, and run `npm run build`. To preview
and check drafts: `npm run build:drafts` (output in `dist-drafts/`, never deployed).

## Web approval page

`/approve/<token>` is served by `/approve-request/`. Its backend does not exist yet. When
`PUBLIC_APPROVE_ENDPOINT` is set, the page posts `{token, approve}` to it and expects
`{ok, data}` or `{ok: false, error: {code}}` with codes `expired` and `invalid`. Without it the
page explains how to use the 6-digit code from the email.

## Deploying to Cloudflare Pages

Project root `web`, build command `npm run build`, output directory `dist`, Node 22 or later.
Add the environment variables from `.env.example`.

## Rules

- No third-party analytics, ad scripts, fonts or images: the build fails on any external resource.
- Colors, type and spacing come from `src/styles/tokens.css` (the tokens in doc 10).
- Voice and vocabulary follow doc 10: "protected time", "pause", "ask your partner", never guilt.
- Every price says it covers both partners (decision M7); use the `price` helpers in the config.
