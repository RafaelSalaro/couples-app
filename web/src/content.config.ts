import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

// Guides (docs/09-website-and-seo.md §7). One Markdown file per guide in src/content/guides/.
// Guides never name the app (the name is not final): the layout adds the call to action.
// `draft: true` keeps a guide out of the build, the sitemap and the guides index.
const guides = defineCollection({
  loader: glob({ pattern: '*.md', base: './src/content/guides' }),
  schema: z.object({
    title: z.string().max(70),
    description: z.string().min(70).max(165),
    /** Short line under the title. */
    lede: z.string(),
    published: z.coerce.date(),
    updated: z.coerce.date().optional(),
    cluster: z.enum(['ideas', 'problem', 'how-to', 'science', 'comparison']),
    draft: z.boolean().default(false),
    /** Planned publication week for drafts (docs/09 §7: one new guide per week). */
    plannedWeek: z.number().int().optional(),
    faq: z.array(z.object({ question: z.string(), answer: z.string() })).min(2),
    sources: z
      .array(z.object({ citation: z.string(), url: z.url().optional() }))
      .default([]),
  }),
});

// Legal drafts live in content/legal/ at the repository root so the same text serves the
// website, the App Store listing and attorney review. Brand tokens such as {{APP_NAME}}
// are filled in by the remark plugin in astro.config.mjs.
const legal = defineCollection({
  loader: glob({ pattern: '*.md', base: '../content/legal' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    status: z.string(),
    version: z.string(),
  }),
});

export const collections = { guides, legal };
