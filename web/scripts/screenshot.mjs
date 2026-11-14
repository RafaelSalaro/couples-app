// Developer helper: full-page screenshots of the built site for visual review.
//   CHROME_PATH=... node scripts/screenshot.mjs <out-dir> [/path/ ...]
// Writes <name>-mobile-light.png, <name>-desktop-dark.png and so on.
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdirSync } from 'node:fs';
import puppeteer from 'puppeteer-core';
import { serveDist } from './static-server.mjs';

const webRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const [outDir, ...paths] = process.argv.slice(2);
mkdirSync(outDir, { recursive: true });
const server = await serveDist(join(webRoot, 'dist'), 4392);
const browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH, headless: true });
const views = [
  { name: 'mobile-light', width: 390, height: 844, scheme: 'light' },
  { name: 'desktop-dark', width: 1280, height: 800, scheme: 'dark' },
];
for (const path of paths.length > 0 ? paths : ['/']) {
  for (const view of views) {
    const page = await browser.newPage();
    await page.setViewport({ width: view.width, height: view.height, deviceScaleFactor: 1 });
    await page.emulateMediaFeatures([
      { name: 'prefers-color-scheme', value: view.scheme },
      { name: 'prefers-reduced-motion', value: 'reduce' },
    ]);
    await page.goto(`http://127.0.0.1:4392${path}`, { waitUntil: 'networkidle0' });
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    if (overflow > 0) console.warn(`${path} ${view.name}: horizontal overflow of ${overflow}px`);
    const file = join(outDir, `${path.replace(/\W+/g, '_').replace(/^_|_$/g, '') || 'home'}-${view.name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    console.log(file);
    await page.close();
  }
}
await browser.close();
server.close();
