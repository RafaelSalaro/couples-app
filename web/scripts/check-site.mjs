// Build-time SEO and hygiene checks on dist/ (docs/09-website-and-seo.md §5).
// Runs as part of `npm run build`; any error fails the build (and CI).
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const webRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
const dist = join(webRoot, process.argv[2] ?? 'dist');
const errors = [];
const warnings = [];
const fail = (page, message) => errors.push(`${page}: ${message}`);

const walk = (dir) =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : [path];
  });

if (!existsSync(dist)) {
  console.error(`check-site: ${dist} does not exist. Run astro build first.`);
  process.exit(1);
}

const files = walk(dist);
const htmlFiles = files.filter((file) => file.endsWith('.html'));
const urlPath = (file) => {
  const rel = '/' + relative(dist, file).split(sep).join('/');
  return rel.replace(/index\.html$/, '');
};
const decode = (text) =>
  text.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>');
const attr = (tag, name) => {
  const match = tag.match(new RegExp(`\\s${name}="([^"]*)"`, 'i'));
  return match ? decode(match[1]) : null;
};
const tags = (html, name) => html.match(new RegExp(`<${name}\\b[^>]*>`, 'gi')) ?? [];

const pages = new Map();
for (const file of htmlFiles) {
  const html = readFileSync(file, 'utf8');
  const ids = new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => m[1]));
  pages.set(urlPath(file), { file, html, ids });
}

const siteUrlMatch = [...pages.values()]
  .map((page) => page.html.match(/<link rel="canonical" href="(https?:\/\/[^/"]+)/))
  .find(Boolean);
const origin = siteUrlMatch ? siteUrlMatch[1] : null;
if (!origin) errors.push('No canonical URL found on any page.');

const seenTitles = new Map();
const seenDescriptions = new Map();
const indexable = [];

for (const [path, { html }] of pages) {
  const metas = tags(html, 'meta');
  const meta = (key, value) => metas.find((tag) => attr(tag, key) === value);
  const noindex = /noindex/.test(attr(meta('name', 'robots') ?? '', 'content') ?? '');

  if (!/<html[^>]*\slang="en"/.test(html)) fail(path, 'missing <html lang>');

  const titles = [...html.matchAll(/<title>([^<]*)<\/title>/g)].map((m) => decode(m[1]).trim());
  if (titles.length !== 1 || !titles[0]) fail(path, `expected exactly one non-empty <title>, found ${titles.length}`);
  const description = attr(meta('name', 'description') ?? '', 'content');
  if (!description) fail(path, 'missing meta description');

  const h1s = (html.match(/<h1\b/g) ?? []).length;
  if (h1s !== 1) fail(path, `expected exactly one <h1>, found ${h1s}`);

  // Heading order: no jumps of more than one level.
  let last = 0;
  for (const match of html.matchAll(/<h([1-6])\b/g)) {
    const level = Number(match[1]);
    if (last && level > last + 1) {
      fail(path, `heading level jumps from h${last} to h${level}`);
      break;
    }
    last = level;
  }

  if (!noindex) {
    indexable.push(path);
    if (titles[0]) {
      if (titles[0].length > 65) warnings.push(`${path}: title is ${titles[0].length} characters (aim for 65 or fewer)`);
      if (seenTitles.has(titles[0])) fail(path, `duplicate title, also on ${seenTitles.get(titles[0])}`);
      seenTitles.set(titles[0], path);
    }
    if (description) {
      if (description.length < 70 || description.length > 165) {
        warnings.push(`${path}: meta description is ${description.length} characters (aim for 70 to 165)`);
      }
      if (seenDescriptions.has(description)) fail(path, `duplicate description, also on ${seenDescriptions.get(description)}`);
      seenDescriptions.set(description, path);
    }
    const canonicals = tags(html, 'link').filter((tag) => attr(tag, 'rel') === 'canonical');
    if (canonicals.length !== 1) fail(path, `expected one canonical link, found ${canonicals.length}`);
    else if (origin && attr(canonicals[0], 'href') !== origin + path) {
      fail(path, `canonical is ${attr(canonicals[0], 'href')}, expected ${origin + path}`);
    }
    for (const property of ['og:title', 'og:description', 'og:url', 'og:image']) {
      if (!attr(meta('property', property) ?? '', 'content')) fail(path, `missing ${property}`);
    }
    if (!meta('name', 'twitter:card')) fail(path, 'missing twitter:card');
    const image = attr(meta('property', 'og:image') ?? '', 'content');
    if (image && origin && !existsSync(join(dist, image.replace(origin, '')))) fail(path, `og:image file missing: ${image}`);
  }

  // Structured data must parse and carry @context and @type.
  for (const match of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) {
    try {
      const data = JSON.parse(match[1]);
      if (!data['@context'] || !data['@type']) fail(path, 'JSON-LD without @context or @type');
      if (data['@type'] === 'FAQPage' && !(data.mainEntity?.length > 0)) fail(path, 'FAQPage without questions');
      if (data['@type'] === 'Article') {
        for (const key of ['headline', 'datePublished', 'author', 'image']) {
          if (!data[key]) fail(path, `Article JSON-LD missing ${key}`);
        }
      }
      if (/aggregateRating|"review"/.test(match[1])) fail(path, 'JSON-LD contains ratings or reviews; none exist yet');
    } catch (error) {
      fail(path, `invalid JSON-LD: ${error.message}`);
    }
  }

  // No third-party scripts, styles, fonts or images (CLAUDE.md: no third-party analytics or ad scripts).
  const external = (value) => value && /^(https?:)?\/\//.test(value) && !(origin && value.startsWith(origin));
  for (const tag of [...tags(html, 'script'), ...tags(html, 'img'), ...tags(html, 'iframe')]) {
    if (external(attr(tag, 'src'))) fail(path, `third-party resource: ${attr(tag, 'src')}`);
  }
  for (const tag of tags(html, 'link')) {
    const rel = attr(tag, 'rel');
    if (['stylesheet', 'preload', 'preconnect', 'dns-prefetch', 'modulepreload'].includes(rel) && external(attr(tag, 'href'))) {
      fail(path, `third-party resource: ${attr(tag, 'href')}`);
    }
  }

  // Words glued to a link or emphasis ("see<a>") mean whitespace was lost in the build.
  const glued = html.match(/[a-z,.:;]<(a|strong|em) [^>]*>[A-Za-z]|[a-z]<\/(a|strong|em)>[a-z]/);
  if (glued) fail(path, `missing space around inline element: "${glued[0]}"`);

  // Images need explicit dimensions and alt text.
  for (const tag of tags(html, 'img')) {
    if (attr(tag, 'alt') === null) fail(path, `image without alt: ${attr(tag, 'src')}`);
    if (!attr(tag, 'width') || !attr(tag, 'height')) fail(path, `image without width/height: ${attr(tag, 'src')}`);
  }

  // Internal links and assets must resolve.
  const refs = [
    ...tags(html, 'a').map((tag) => attr(tag, 'href')),
    ...tags(html, 'link').map((tag) => attr(tag, 'href')),
    ...tags(html, 'script').map((tag) => attr(tag, 'src')),
    ...tags(html, 'img').map((tag) => attr(tag, 'src')),
  ].filter(Boolean);
  for (const ref of refs) {
    let target = ref;
    if (origin && target.startsWith(origin)) target = target.slice(origin.length) || '/';
    if (/^(https?:|mailto:|tel:|data:)/.test(target)) continue;
    if (!target.startsWith('/') && !target.startsWith('#')) {
      fail(path, `relative link "${ref}" (use root-relative links)`);
      continue;
    }
    const [rawPath, fragment] = target.split('#');
    const targetPath = rawPath === '' ? path : rawPath.split('?')[0];
    const page = pages.get(targetPath);
    if (!page && !existsSync(join(dist, targetPath))) {
      fail(path, `broken link: ${ref}`);
      continue;
    }
    if (!page && !/\.[a-z0-9]+$/i.test(targetPath) && !targetPath.endsWith('/')) fail(path, `link without trailing slash: ${ref}`);
    if (page && fragment && !page.ids.has(fragment)) fail(path, `broken anchor: ${ref}`);
  }
}

// Guides link to the product pages (docs/09 §5).
for (const [path, { html }] of pages) {
  if (/^\/guides\/[^/]+\/$/.test(path)) {
    for (const required of ['/how-it-works/', '/pricing/']) {
      if (!html.includes(`href="${required}"`)) fail(path, `guide must link to ${required}`);
    }
  }
}

// Sitemap and robots.
const sitemapFiles = files.filter((file) => /sitemap-\d+\.xml$/.test(file));
if (!existsSync(join(dist, 'sitemap-index.xml')) || sitemapFiles.length === 0) {
  errors.push('sitemap-index.xml or sitemap-0.xml is missing');
} else if (origin) {
  const listed = new Set(
    sitemapFiles.flatMap((file) => [...readFileSync(file, 'utf8').matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1])),
  );
  for (const path of indexable) if (!listed.has(origin + path)) errors.push(`sitemap is missing ${path}`);
  for (const url of listed) {
    const path = url.replace(origin, '');
    if (!indexable.includes(path)) errors.push(`sitemap lists a page that is missing or noindex: ${path}`);
  }
}
const robotsPath = join(dist, 'robots.txt');
if (!existsSync(robotsPath)) errors.push('robots.txt is missing');
else if (!/^Sitemap: https?:\/\/.+\/sitemap-index\.xml$/m.test(readFileSync(robotsPath, 'utf8'))) {
  errors.push('robots.txt does not point to the sitemap');
}

// Deep-link files.
for (const name of ['.well-known/apple-app-site-association', '.well-known/assetlinks.json']) {
  try {
    JSON.parse(readFileSync(join(dist, name), 'utf8'));
  } catch {
    errors.push(`${name} is missing or not valid JSON`);
  }
}

// JavaScript budget on the home page: under 50 KB (docs/09 §2).
const home = pages.get('/');
if (home) {
  const inline = [...home.html.matchAll(/<script(?![^>]*ld\+json)[^>]*>([\s\S]*?)<\/script>/g)].reduce((sum, m) => sum + m[1].length, 0);
  const linked = tags(home.html, 'script')
    .map((tag) => attr(tag, 'src'))
    .filter(Boolean)
    .reduce((sum, src) => sum + statSync(join(dist, src)).size, 0);
  const total = inline + linked;
  if (total > 50_000) errors.push(`home page JavaScript is ${total} bytes (budget 50,000)`);
  else console.log(`check-site: home page JavaScript ${total} bytes (budget 50,000)`);
}

// The brand name, company and domain come from src/config/site.ts only.
const sourceFiles = ['src/pages', 'src/components', 'src/layouts', 'src/content', 'src/data', 'src/lib']
  .map((dir) => join(webRoot, dir))
  .filter(existsSync)
  .flatMap(walk);
for (const file of sourceFiles) {
  const text = readFileSync(file, 'utf8');
  for (const literal of ['Couples App', 'example.com', 'Company name']) {
    if (text.includes(literal)) errors.push(`${relative(webRoot, file)}: hard-coded "${literal}" (use src/config/site.ts)`);
  }
}

for (const warning of warnings) console.warn(`check-site warning: ${warning}`);
if (errors.length > 0) {
  for (const error of errors) console.error(`check-site error: ${error}`);
  console.error(`check-site: ${errors.length} error(s) in ${pages.size} pages`);
  process.exit(1);
}
console.log(`check-site: ${pages.size} pages, ${indexable.length} indexable, no errors, ${warnings.length} warning(s)`);
