// Local test double for the `waitlist_join` Edge Function
// (docs/05-data-model-and-api.md §3). It follows the documented contract:
//   POST {email, source}  ->  {ok: true, data: {...}}
//                         or  {ok: false, error: {code, message}}   (codes: invalid_email, rate_limited)
// It stores signups in memory only and sends no email. It exists so the form can be
// exercised end to end without a Supabase or Resend account. Never deploy it.
//
//   npm run mock:waitlist            # http://127.0.0.1:8787/waitlist_join
//   GET /signups                     # what was received (for tests)
import { createServer } from 'node:http';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const RATE_LIMIT = 5; // requests per minute per address, like the real function should enforce

export function createMockWaitlist() {
  const signups = [];
  const hits = new Map();

  const server = createServer(async (req, res) => {
    const cors = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'content-type, authorization, apikey',
    };
    const send = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json', ...cors });
      res.end(JSON.stringify(body));
    };
    const url = new URL(req.url, 'http://localhost');

    if (req.method === 'OPTIONS') {
      res.writeHead(204, cors);
      return res.end();
    }
    if (req.method === 'GET' && url.pathname === '/signups') return send(200, { ok: true, data: signups });
    if (req.method !== 'POST' || url.pathname !== '/waitlist_join') {
      return send(404, { ok: false, error: { code: 'not_found', message: 'Not found' } });
    }

    let raw = '';
    for await (const chunk of req) raw += chunk;
    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return send(400, { ok: false, error: { code: 'invalid_email', message: 'Body must be JSON' } });
    }
    const email = String(body?.email ?? '').trim().toLowerCase();
    const source = String(body?.source ?? 'website').slice(0, 64);
    if (!EMAIL.test(email)) {
      return send(400, { ok: false, error: { code: 'invalid_email', message: 'Enter a valid email address' } });
    }

    const now = Date.now();
    const recent = (hits.get(email) ?? []).filter((t) => now - t < 60_000);
    recent.push(now);
    hits.set(email, recent);
    if (recent.length > RATE_LIMIT) {
      return send(429, { ok: false, error: { code: 'rate_limited', message: 'Too many requests' } });
    }

    // Idempotent: joining twice is not an error (and does not reveal who is on the list).
    if (!signups.some((s) => s.email === email)) {
      signups.push({ email, source, confirmed_at: null, created_at: new Date(now).toISOString() });
      console.log(`[mock waitlist] ${email} (${source}) - a real backend would now send the double opt-in email`);
    }
    return send(200, { ok: true, data: { status: 'pending_confirmation' } });
  });

  return { server, signups };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.MOCK_WAITLIST_PORT ?? 8787);
  createMockWaitlist().server.listen(port, '127.0.0.1', () => {
    console.log(`Mock waitlist_join at http://127.0.0.1:${port}/waitlist_join`);
  });
}
