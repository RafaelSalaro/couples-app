import type { APIRoute, GetStaticPaths } from 'astro';
import { ogPages } from '../../config/og-pages';
import { renderOgImage } from '../../lib/og';

export const getStaticPaths: GetStaticPaths = async () =>
  Object.entries(ogPages).map(([slug, props]) => ({ params: { slug }, props }));

export const GET: APIRoute = async ({ props }) => {
  const png = await renderOgImage(props as { title: string; kicker?: string });
  return new Response(png as BodyInit, { headers: { 'Content-Type': 'image/png' } });
};
