// Developer helper for visual review of the built site (W3):
//   CHROME_PATH=... node scripts/shots.mjs <out-dir> [--full] [--motion] [--at=0,0.5,1] [/path/ ...]
// Takes every path in light and dark at phone and desktop widths. By default each shot is one
// viewport at the given scroll fractions with motion on; --full takes whole pages with reduced motion.
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync } from 'node:fs';
import puppeteer from 'puppeteer-core';
import { serveDist } from './static-server.mjs';

const webRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const args = process.argv.slice(2);
const outDir = args.shift();
const full = args.includes('--full');
const at = (args.find((a) => a.startsWith('--at='))?.slice(5) ?? '0').split(',').map(Number);
const only = args.find((a) => a.startsWith('--only='))?.slice(7);
const paths = args.filter((a) => a.startsWith('/'));
mkdirSync(outDir, { recursive: true });
const server = await serveDist(join(webRoot, 'dist'), 4393);
const browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH, headless: true });
const views = [
  { name: 'phone-light', width: 390, height: 844, scheme: 'light' },
  { name: 'phone-dark', width: 390, height: 844, scheme: 'dark' },
  { name: 'desktop-light', width: 1440, height: 900, scheme: 'light' },
  { name: 'desktop-dark', width: 1440, height: 900, scheme: 'dark' },
].filter((view) => !only || view.name.includes(only));
for (const path of paths.length > 0 ? paths : ['/']) {
  for (const view of views) {
    const page = await browser.newPage();
    await page.setViewport({ width: view.width, height: view.height, deviceScaleFactor: 1 });
    await page.emulateMediaFeatures([
      { name: 'prefers-color-scheme', value: view.scheme },
      { name: 'prefers-reduced-motion', value: full ? 'reduce' : 'no-preference' },
    ]);
    await page.goto(`http://127.0.0.1:4393${path}`, { waitUntil: 'networkidle0' });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    if (overflow > 0) console.warn(`${path} ${view.name}: horizontal overflow of ${overflow}px`);
    const base = `${path.replace(/\W+/g, '_').replace(/^_|_$/g, '') || 'home'}-${view.name}`;
    if (full) {
      await page.screenshot({ path: join(outDir, `${base}.png`), fullPage: true });
    } else {
      for (const fraction of at) {
        await page.evaluate((f) => {
          document.documentElement.style.scrollBehavior = 'auto';
          scrollTo(0, (document.documentElement.scrollHeight - innerHeight) * f);
        }, fraction);
        await new Promise((resolve) => setTimeout(resolve, 900));
        await page.screenshot({ path: join(outDir, `${base}-${String(Math.round(fraction * 100)).padStart(3, '0')}.png`) });
      }
    }
    await page.close();
  }
}
await browser.close();
server.close();
