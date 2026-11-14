// Unit tests for the waitlist client (src/lib/waitlist.ts). Run with `npm test`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { submitWaitlist, isValidEmail, messages } from '../src/lib/waitlist.ts';

const endpoint = 'https://functions.test/waitlist_join';
const json = (status, body) => new Response(JSON.stringify(body), { status });

test('isValidEmail', () => {
  for (const good of ['a@b.co', 'first.last+tag@sub.domain.org']) assert.equal(isValidEmail(good), true, good);
  for (const bad of ['', 'a', 'a@b', '@b.co', 'a b@c.co', 'a@b.c', `${'x'.repeat(250)}@b.co`]) {
    assert.equal(isValidEmail(bad), false, bad);
  }
});

test('sends trimmed, lower-cased email and source as JSON', async () => {
  let seen;
  const result = await submitWaitlist({
    endpoint,
    email: '  Ana@Example.ORG ',
    source: 'home-hero',
    fetchImpl: async (url, init) => {
      seen = { url, init };
      return json(200, { ok: true, data: {} });
    },
  });
  assert.deepEqual(result, { ok: true, message: messages.success });
  assert.equal(seen.url, endpoint);
  assert.equal(seen.init.method, 'POST');
  assert.deepEqual(JSON.parse(seen.init.body), { email: 'ana@example.org', source: 'home-hero' });
  assert.equal(seen.init.headers.Authorization, undefined);
});

test('adds Supabase headers only when an anon key is configured', async () => {
  let headers;
  await submitWaitlist({
    endpoint,
    anonKey: 'anon',
    email: 'a@b.co',
    source: 's',
    fetchImpl: async (_url, init) => {
      headers = init.headers;
      return json(200, { ok: true });
    },
  });
  assert.equal(headers.apikey, 'anon');
  assert.equal(headers.Authorization, 'Bearer anon');
});

test('invalid email never calls the backend', async () => {
  let called = false;
  const result = await submitWaitlist({ endpoint, email: 'nope', source: 's', fetchImpl: async () => ((called = true), json(200, {})) });
  assert.equal(result.ok, false);
  assert.equal(result.code, 'invalid_email');
  assert.equal(called, false);
});

test('honeypot is dropped with a success message and no request', async () => {
  let called = false;
  const result = await submitWaitlist({ endpoint, email: 'a@b.co', source: 's', honeypot: 'x', fetchImpl: async () => ((called = true), json(200, {})) });
  assert.equal(result.ok, true);
  assert.equal(called, false);
});

test('missing endpoint is reported plainly', async () => {
  const result = await submitWaitlist({ endpoint: '', email: 'a@b.co', source: 's' });
  assert.equal(result.code, 'not_configured');
});

test('maps backend errors to gentle messages', async () => {
  const run = (response) => submitWaitlist({ endpoint, email: 'a@b.co', source: 's', fetchImpl: async () => response });
  assert.equal((await run(json(429, { ok: false, error: { code: 'rate_limited' } }))).code, 'rate_limited');
  assert.equal((await run(json(429, {}))).code, 'rate_limited');
  assert.equal((await run(json(400, { ok: false, error: { code: 'invalid_email' } }))).code, 'invalid_email');
  assert.equal((await run(json(500, { ok: false, error: { code: 'boom' } }))).code, 'unknown');
  assert.equal((await run(new Response('<html>', { status: 502 }))).code, 'unknown');
  assert.equal((await run(json(200, { ok: false }))).code, 'unknown');
});

test('network failure and timeout', async () => {
  const offline = await submitWaitlist({ endpoint, email: 'a@b.co', source: 's', fetchImpl: async () => Promise.reject(new TypeError('offline')) });
  assert.equal(offline.code, 'network');
  const slow = await submitWaitlist({
    endpoint,
    email: 'a@b.co',
    source: 's',
    timeoutMs: 20,
    fetchImpl: (_url, init) => new Promise((_resolve, reject) => init.signal.addEventListener('abort', () => reject(new Error('aborted')))),
  });
  assert.equal(slow.code, 'network');
});

test('no message scolds or uses forbidden vocabulary', () => {
  for (const text of Object.values(messages)) {
    assert.doesNotMatch(text, /\b(denied|blocked|failed|error|invalid|forbidden)\b/i, text);
  }
});
