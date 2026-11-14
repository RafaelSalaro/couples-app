// Validates content/challenges/library.json and writes supabase/seeds/10_challenge_library.sql.
//
//   node content/challenges/build-seed.mjs          # validate and write the seed
//   node content/challenges/build-seed.mjs --check  # validate, and fail if the seed is out of date
//
// Rules come from the challenges table (supabase/migrations) and supabase/README.md:
// title 1-80 characters and unique per relationship type among presets, description up to 280,
// minutes 5-60, category one of the enum values, tier 'premium'.
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(fileURLToPath(new URL('.', import.meta.url)), '..', '..');
const libraryPath = join(root, 'content/challenges/library.json');
const presetPath = join(root, 'supabase/seeds/00_preset_challenges.sql');
const seedPath = join(root, 'supabase/seeds/10_challenge_library.sql');

const library = JSON.parse(readFileSync(libraryPath, 'utf8'));
const categories = Object.keys(library.categories);
const errors = [];

// Titles of the free presets, read from the backend lane's seed so the two never overlap.
const presetTitles = existsSync(presetPath)
  ? [...readFileSync(presetPath, 'utf8').matchAll(/\('romantic', '((?:[^']|'')*)'/g)].map((m) => m[1].replace(/''/g, "'"))
  : [];
const normalize = (text) => text.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const taken = new Set(presetTitles.map(normalize));

// Vocabulary from docs/10-brand-and-design-system.md §2: words that never appear in challenge copy.
const forbidden = /\b(block(ed|ing)?|permission|penalt(y|ies)|fail(ed|ure)?|violation|points?|addict(ion|ed)?|punish\w*|ban(ned)?|must|forbidden)\b/i;

for (const [index, challenge] of library.challenges.entries()) {
  const where = `#${index + 1} "${challenge.title}"`;
  const { title, description, minutes, category, shared } = challenge;
  if (typeof title !== 'string' || title.length < 1 || title.length > 80) errors.push(`${where}: title must be 1-80 characters`);
  if (typeof description !== 'string' || description.length < 1 || description.length > 280) errors.push(`${where}: description must be 1-280 characters`);
  if (!Number.isInteger(minutes) || minutes < 5 || minutes > 60 || minutes % 5 !== 0) errors.push(`${where}: minutes must be a multiple of 5 from 5 to 60`);
  if (!categories.includes(category)) errors.push(`${where}: unknown category "${category}"`);
  if (typeof shared !== 'boolean') errors.push(`${where}: shared must be true or false`);
  if (forbidden.test(`${title} ${description}`)) errors.push(`${where}: uses a word the brand voice avoids`);
  const key = normalize(title ?? '');
  if (taken.has(key)) errors.push(`${where}: duplicate title (in the library or the free presets)`);
  taken.add(key);
}
if (library.challenges.length < 60) errors.push(`library has ${library.challenges.length} challenges; the target is 60 or more`);

if (errors.length > 0) {
  for (const error of errors) console.error(error);
  process.exit(1);
}

const quote = (text) => `'${text.replace(/'/g, "''")}'`;
const rows = library.challenges
  .map(
    (c) =>
      `  (${quote(library.relationship_type)}, ${quote(c.title)}, ${quote(c.description)}, ${c.minutes}, ${quote(c.category)}, ${c.shared}, ${quote(library.tier)})`,
  )
  .join(',\n');

const sql = `-- Premium challenge library (docs/03-feature-spec.md §8): ${library.challenges.length} preset challenges for couples.
-- GENERATED from content/challenges/library.json by content/challenges/build-seed.mjs.
-- Do not edit by hand: change the JSON and run \`node content/challenges/build-seed.mjs\`.
-- Safe to re-run. The 5 free presets are in 00_preset_challenges.sql.
insert into public.challenges (relationship_type, title, description, minutes, category, is_shared, tier)
values
${rows}
on conflict (relationship_type, title) where pair_id is null do nothing;
`;

const summary = categories
  .map((id) => `${library.categories[id]} ${library.challenges.filter((c) => c.category === id).length}`)
  .join(', ');

if (process.argv.includes('--check')) {
  if (!existsSync(seedPath) || readFileSync(seedPath, 'utf8') !== sql) {
    console.error('supabase/seeds/10_challenge_library.sql is out of date. Run node content/challenges/build-seed.mjs');
    process.exit(1);
  }
  console.log(`Challenge library OK: ${library.challenges.length} challenges (${summary}); seed is up to date.`);
} else {
  writeFileSync(seedPath, sql);
  console.log(`Wrote ${seedPath}: ${library.challenges.length} challenges (${summary}).`);
}
