import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import { loadEnv } from 'vite';

// Make .env values visible to src/config/site.ts, which reads process.env at build time.
const mode = process.env.NODE_ENV === 'development' ? 'development' : 'production';
for (const [key, value] of Object.entries(loadEnv(mode, process.cwd(), ''))) {
  if (process.env[key] === undefined) process.env[key] = value;
}

const domain = process.env.SITE_DOMAIN?.trim() || 'example.com';

// Pages that must never be indexed or listed in the sitemap.
const privatePaths = ['/invite/', '/approve-request/', '/waitlist/confirmed/', '/404/'];

export default defineConfig({
  site: `https://${domain}`,
  output: 'static',
  // Astro's HTML compression drops the space at a line break before an inline element
  // ("see<a>"), so it stays off; Cloudflare compresses responses anyway.
  compressHTML: false,
  trailingSlash: 'always',
  build: { format: 'directory', inlineStylesheets: 'always' },
  integrations: [
    sitemap({
      filter: (page) => !privatePaths.some((path) => new URL(page).pathname.startsWith(path)),
    }),
  ],
});
