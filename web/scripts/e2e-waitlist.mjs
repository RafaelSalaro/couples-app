// End-to-end test of the waitlist form in a real browser, against the local test
// double of the `waitlist_join` Edge Function (scripts/mock-waitlist.mjs).
//
//   CHROME_PATH=/path/to/chrome npm run test:e2e
//
// It builds the site into dist-e2e/ with PUBLIC_WAITLIST_ENDPOINT pointing at the
// mock, serves it, and drives the form the way a visitor would.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import puppeteer from 'puppeteer-core';
import { createMockWaitlist } from './mock-waitlist.mjs';
import { serveDist } from './static-server.mjs';

const webRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const chromePath = process.env.CHROME_PATH;
if (!chromePath || !existsSync(chromePath)) {
  console.error('Set CHROME_PATH to a Chrome or Chromium binary.');
  process.exit(1);
}

const MOCK_PORT = 8787;
const SITE_PORT = 4390;
const endpoint = `http://127.0.0.1:${MOCK_PORT}/waitlist_join`;

console.log('Building site against the mock endpoint…');
execFileSync('npx', ['astro', 'build', '--outDir', 'dist-e2e', '--silent'], {
  cwd: webRoot,
  stdio: 'inherit',
  env: { ...process.env, PUBLIC_WAITLIST_ENDPOINT: endpoint },
});

const mock = createMockWaitlist();
await new Promise((resolve) => mock.server.listen(MOCK_PORT, '127.0.0.1', resolve));
const site = await serveDist(join(webRoot, 'dist-e2e'), SITE_PORT);
const browser = await puppeteer.launch({ executablePath: chromePath, headless: true });

let failed = 0;
const step = async (name, fn) => {
  try {
    await fn();
    console.log(`  ok   ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`  FAIL ${name}\n       ${error.message}`);
  }
};

const open = async (path = '/') => {
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${SITE_PORT}${path}`, { waitUntil: 'networkidle0' });
  return page;
};
const submit = async (page, form, email) => {
  await page.$eval(`${form} input[name="email"]`, (el) => (el.value = ''));
  await page.type(`${form} input[name="email"]`, email);
  await page.click(`${form} button[type="submit"]`);
  await page.waitForFunction(
    (selector) => {
      const el = document.querySelector(`${selector} [role="status"]`);
      return el && el.textContent && el.textContent !== 'One moment…';
    },
    {},
    form,
  );
  return page.$eval(`${form} [role="status"]`, (el) => el.textContent);
};

try {
  await step('invalid email is caught with a kind message and nothing is sent', async () => {
    const page = await open();
    const text = await submit(page, '#hero-waitlist', 'not-an-email');
    assert.match(text, /doesn't look quite right/);
    assert.equal(mock.signups.length, 0);
    await page.close();
  });

  await step('valid email reaches the backend with its source and shows the confirm message', async () => {
    const page = await open();
    const text = await submit(page, '#hero-waitlist', 'Ana@Example.org');
    assert.match(text, /Check your inbox/);
    assert.deepEqual(
      mock.signups.map(({ email, source, confirmed_at }) => ({ email, source, confirmed_at })),
      [{ email: 'ana@example.org', source: 'home-hero', confirmed_at: null }],
    );
    await page.close();
  });

  await step('second form on the page works and records its own source', async () => {
    const page = await open();
    const text = await submit(page, '#footer-waitlist', 'ben@example.org');
    assert.match(text, /Check your inbox/);
    assert.equal(mock.signups.at(-1).source, 'home-footer');
    await page.close();
  });

  await step('joining twice is not an error and does not duplicate', async () => {
    const page = await open();
    const text = await submit(page, '#hero-waitlist', 'ana@example.org');
    assert.match(text, /Check your inbox/);
    assert.equal(mock.signups.filter((s) => s.email === 'ana@example.org').length, 1);
    await page.close();
  });

  await step('rate limit from the backend shows a gentle message', async () => {
    const page = await open();
    let text = '';
    for (let i = 0; i < 6; i += 1) text = await submit(page, '#hero-waitlist', 'cara@example.org');
    assert.match(text, /give it a minute/);
    await page.close();
  });

  await step('honeypot submissions are dropped silently', async () => {
    const page = await open();
    const before = mock.signups.length;
    await page.$eval('#hero-waitlist input[name="website"]', (el) => (el.value = 'https://spam.test'));
    const text = await submit(page, '#hero-waitlist', 'bot@example.org');
    assert.match(text, /Check your inbox/);
    assert.equal(mock.signups.length, before);
    await page.close();
  });

  await step('backend unreachable shows a try-again message', async () => {
    const page = await open();
    await page.setRequestInterception(true);
    page.on('request', (request) => (request.url().includes('waitlist_join') ? request.abort() : request.continue()));
    const text = await submit(page, '#hero-waitlist', 'dan@example.org');
    assert.match(text, /couldn't reach the waitlist/);
    await page.close();
  });

  await step('invite link fallback route serves the invite page with its own waitlist form', async () => {
    const page = await open('/i/abc123token');
    assert.match(await page.$eval('h1', (el) => el.textContent), /pair with you/);
    assert.match(await page.$eval('meta[name="robots"]', (el) => el.content), /noindex/);
    const text = await submit(page, '#invite-waitlist', 'eve@example.org');
    assert.match(text, /Check your inbox/);
    assert.equal(mock.signups.at(-1).source, 'invite');
    await page.close();
  });

  await step('no requests leave the site except to the waitlist endpoint', async () => {
    const page = await browser.newPage();
    const hosts = new Set();
    page.on('request', (request) => hosts.add(new URL(request.url()).host));
    await page.goto(`http://127.0.0.1:${SITE_PORT}/`, { waitUntil: 'networkidle0' });
    await submit(page, '#hero-waitlist', 'fay@example.org');
    assert.deepEqual([...hosts].sort(), [`127.0.0.1:${SITE_PORT}`, `127.0.0.1:${MOCK_PORT}`].sort());
    await page.close();
  });
} finally {
  await browser.close();
  site.close();
  mock.server.close();
}

console.log(failed === 0 ? 'Waitlist end-to-end: all steps passed.' : `Waitlist end-to-end: ${failed} step(s) failed.`);
process.exit(failed === 0 ? 0 : 1);
