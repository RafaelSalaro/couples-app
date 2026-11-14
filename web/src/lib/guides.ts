import { getCollection, type CollectionEntry } from 'astro:content';

export type Guide = CollectionEntry<'guides'>;

export const clusterLabel: Record<Guide['data']['cluster'], string> = {
  ideas: 'Ideas',
  problem: 'Understanding it',
  'how-to': 'How-to',
  science: 'Research',
  comparison: 'Comparison',
};

// Drafts never reach a normal build. To preview them locally:
//   npm run build:drafts
const includeDrafts = process.env.GUIDES_INCLUDE_DRAFTS === 'true';

/** Published guides, newest first. */
export async function publishedGuides(): Promise<Guide[]> {
  const guides = await getCollection('guides', ({ data }) => includeDrafts || !data.draft);
  return guides.sort(
    (a, b) => b.data.published.getTime() - a.data.published.getTime() || a.id.localeCompare(b.id),
  );
}

export const readingMinutes = (body: string | undefined): number =>
  Math.max(1, Math.round((body ?? '').split(/\s+/).filter(Boolean).length / 220));

export const formatDate = (date: Date): string =>
  date.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric', timeZone: 'UTC' });
