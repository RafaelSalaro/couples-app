import type { APIRoute, GetStaticPaths } from 'astro';
import { ogPages } from '../../config/og-pages';
import { renderOgImage } from '../../lib/og';
import { publishedGuides, clusterLabel } from '../../lib/guides';

export const getStaticPaths: GetStaticPaths = async () => {
  const guides = await publishedGuides();
  return [
    ...Object.entries(ogPages).map(([slug, props]) => ({ params: { slug }, props })),
    ...guides.map((guide) => ({
      params: { slug: `guide-${guide.id}` },
      props: { title: guide.data.title, kicker: `Guide · ${clusterLabel[guide.data.cluster]}` },
    })),
  ];
};

export const GET: APIRoute = async ({ props }) => {
  const png = await renderOgImage(props as { title: string; kicker?: string });
  return new Response(png as BodyInit, { headers: { 'Content-Type': 'image/png' } });
};
