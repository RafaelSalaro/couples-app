import type { APIRoute, GetStaticPaths } from 'astro';
import { renderIcon } from '../lib/og';

export const getStaticPaths: GetStaticPaths = () => [
  { params: { icon: 'apple-touch-icon' }, props: { size: 180 } },
  { params: { icon: 'logo' }, props: { size: 512 } },
];

export const GET: APIRoute = ({ props }) =>
  new Response(renderIcon((props as { size: number }).size) as BodyInit, {
    headers: { 'Content-Type': 'image/png' },
  });
