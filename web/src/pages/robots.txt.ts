import type { APIRoute } from 'astro';
import { absoluteUrl } from '../config/site';

export const GET: APIRoute = () =>
  new Response(
    [
      'User-agent: *',
      'Allow: /',
      // Private, token-bearing or utility routes.
      'Disallow: /i/',
      'Disallow: /approve/',
      'Disallow: /invite/',
      'Disallow: /approve-request/',
      'Disallow: /waitlist/',
      '',
      `Sitemap: ${absoluteUrl('/sitemap-index.xml')}`,
      '',
    ].join('\n'),
    { headers: { 'Content-Type': 'text/plain; charset=utf-8' } },
  );
