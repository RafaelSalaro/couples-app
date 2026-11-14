// Single place for the brand name, company, domain, prices and launch state.
// The app name, company and domain are not final (docs/02-decisions-log.md P22, E2).
// Change them here (or through the environment variables in .env.example);
// never hard-code them in pages, components or content.
//
// Values are read at build time only. astro.config.mjs loads .env files into
// process.env before this module is evaluated.

const env = (key: string, fallback: string): string => {
  const value = typeof process !== 'undefined' ? process.env[key] : undefined;
  return value && value.trim() !== '' ? value.trim() : fallback;
};

const domain = env('SITE_DOMAIN', 'example.com');

export const site = {
  /** Display name of the app. Placeholder until the name is chosen. */
  name: env('SITE_NAME', 'Couples App'),
  /** Legal name of the company that publishes the app. Placeholder. */
  company: env('SITE_COMPANY', '[Company name] LLC'),
  domain,
  url: `https://${domain}`,
  tagline: 'Less scrolling. More us.',
  description:
    'Pause distracting apps on a shared schedule and unlock time together. Not about control. About being intentional and present with each other.',
  supportEmail: env('SITE_SUPPORT_EMAIL', `support@${domain}`),
  privacyEmail: env('SITE_PRIVACY_EMAIL', `privacy@${domain}`),
  pressEmail: env('SITE_PRESS_EMAIL', `press@${domain}`),
  locale: 'en-US',

  /** Before launch the site collects waitlist emails; after launch it shows store badges. */
  launched: env('SITE_LAUNCHED', 'false') === 'true',
  appStoreUrl: env('APP_STORE_URL', ''),
  googlePlayUrl: env('GOOGLE_PLAY_URL', ''),

  /** Deep links (docs/06-ios-app.md §9). Team ID is unknown until the Apple account exists. */
  appleTeamId: env('APPLE_TEAM_ID', 'TEAMID0000'),
  iosBundleId: env('IOS_BUNDLE_ID', 'com.example.couplesapp'),

  /** Waitlist: the `waitlist_join` Edge Function (docs/05-data-model-and-api.md §3). */
  waitlistEndpoint: env('PUBLIC_WAITLIST_ENDPOINT', ''),
  /** Supabase anon key (public by design). Sent as a header only when set. */
  supabaseAnonKey: env('PUBLIC_SUPABASE_ANON_KEY', ''),
  /** Web approval for partners without the app (docs/08-android-app.md §1). Not built on the backend yet. */
  approveEndpoint: env('PUBLIC_APPROVE_ENDPOINT', ''),

  /** Prices (decision M7). Every price shown must say it covers both partners. */
  pricing: {
    currency: 'USD',
    yearly: '39.99',
    lifetime: '119.99',
    trialDays: 14,
    perPersonYearly: 'about $20 per person',
  },

  /** Decision P25: adults only. */
  minimumAge: 18,
} as const;

export const price = {
  yearly: `$${site.pricing.yearly}`,
  lifetime: `$${site.pricing.lifetime}`,
  /** Always use these full phrases when showing a price. */
  yearlyForBoth: `$${site.pricing.yearly} a year for both of you`,
  lifetimeForBoth: `$${site.pricing.lifetime} once for both of you`,
};

export const absoluteUrl = (path: string): string =>
  new URL(path, site.url).toString();
