// Runs Lighthouse (mobile and desktop) against the built site in dist/ and prints
// the four category scores per page. Exits non-zero if any score is under 95
// (docs/09-website-and-seo.md §2).
//
//   npm run build && CHROME_PATH=/path/to/chrome npm run lighthouse [-- /path/ /other/]
//
// The domain in this build is a placeholder, so the SEO audit "is-crawlable" and
// canonical checks run against the local server address.
import { execFile } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { serveDist } from './static-server.mjs';

const run = promisify(execFile);
const webRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const chromePath = process.env.CHROME_PATH;
if (!chromePath || !existsSync(chromePath)) {
  console.error('Set CHROME_PATH to a Chrome or Chromium binary.');
  process.exit(1);
}

const paths = process.argv.slice(2).length > 0 ? process.argv.slice(2) : ['/'];
const port = 4391;
const outDir = join(webRoot, '.lighthouse');
mkdirSync(outDir, { recursive: true });
const server = await serveDist(join(webRoot, 'dist'), port);
const categories = ['performance', 'accessibility', 'best-practices', 'seo'];
let low = 0;

try {
  for (const path of paths) {
    for (const preset of ['mobile', 'desktop']) {
      const out = join(outDir, `${path.replace(/\W+/g, '_') || 'home'}-${preset}.json`);
      await run(
        join(webRoot, 'node_modules/.bin/lighthouse'),
        [
          `http://127.0.0.1:${port}${path}`,
          '--quiet',
          '--output=json',
          `--output-path=${out}`,
          `--only-categories=${categories.join(',')}`,
          '--chrome-flags=--headless=new --no-sandbox',
          ...(preset === 'desktop' ? ['--preset=desktop'] : []),
        ],
        { env: { ...process.env, CHROME_PATH: chromePath }, maxBuffer: 64 * 1024 * 1024 },
      );
      const report = JSON.parse(readFileSync(out, 'utf8'));
      const scores = categories.map((id) => Math.round(report.categories[id].score * 100));
      if (scores.some((score) => score < 95)) low += 1;
      const lcp = report.audits['largest-contentful-paint']?.displayValue ?? '?';
      const cls = report.audits['cumulative-layout-shift']?.displayValue ?? '?';
      console.log(
        `${path.padEnd(28)} ${preset.padEnd(8)} perf ${scores[0]}  a11y ${scores[1]}  best ${scores[2]}  seo ${scores[3]}  LCP ${lcp}  CLS ${cls}`,
      );
      for (const id of categories) {
        for (const ref of report.categories[id].auditRefs) {
          const audit = report.audits[ref.id];
          if (audit.score !== null && audit.score < 0.9 && ref.weight > 0) console.log(`    - ${id}: ${audit.id} (${audit.displayValue ?? audit.title})`);
        }
      }
    }
  }
} finally {
  server.close();
}
process.exit(low === 0 ? 0 : 1);
