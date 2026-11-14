// Open Graph images and icons, generated at build time in brand style (docs/09 §5).
// satori lays out text with the brand fonts and resvg renders the PNG, so the
// output does not depend on fonts installed on the build machine.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import satori from 'satori';
import { Resvg } from '@resvg/resvg-js';
import { site } from '../config/site';

const require = createRequire(import.meta.url);
const font = (pkg: string, file: string) => readFileSync(require.resolve(`${pkg}/files/${file}`));

const fonts = [
  { name: 'Fraunces', data: font('@fontsource/fraunces', 'fraunces-latin-500-normal.woff'), weight: 500 as const, style: 'normal' as const },
  { name: 'Instrument Sans', data: font('@fontsource/instrument-sans', 'instrument-sans-latin-400-normal.woff'), weight: 400 as const, style: 'normal' as const },
  { name: 'Instrument Sans', data: font('@fontsource/instrument-sans', 'instrument-sans-latin-600-normal.woff'), weight: 600 as const, style: 'normal' as const },
];

// Light-theme tokens (docs/10 §3).
const color = { surface: '#FBF6F0', ink: '#2A211C', muted: '#6B5E55', hearth: '#AD472E', glow: '#E9A23B', line: '#E5D8C8' };

type Node = { type: string; props: Record<string, unknown> };
const h = (type: string, style: Record<string, unknown>, children?: unknown): Node => ({
  type,
  props: { style, children },
});

const mark = (size: number): Node =>
  h('div', { display: 'flex', width: size * 1.6, height: size, position: 'relative' }, [
    h('div', { position: 'absolute', left: 0, top: 0, width: size, height: size, borderRadius: size, background: color.hearth }),
    h('div', { position: 'absolute', left: size * 0.6, top: 0, width: size, height: size, borderRadius: size, background: color.glow, opacity: 0.88 }),
  ]);

export async function renderOgImage(input: { title: string; kicker?: string }): Promise<Uint8Array> {
  const titleSize = input.title.length > 60 ? 60 : input.title.length > 34 ? 72 : 92;
  const tree = h(
    'div',
    {
      width: 1200,
      height: 630,
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'space-between',
      padding: 72,
      background: color.surface,
      color: color.ink,
      fontFamily: 'Instrument Sans',
    },
    [
      h('div', { display: 'flex', alignItems: 'center', gap: 20 }, [
        mark(56),
        h('div', { fontFamily: 'Fraunces', fontSize: 40, fontWeight: 500 }, site.name),
      ]),
      h('div', { display: 'flex', flexDirection: 'column', gap: 20 }, [
        ...(input.kicker
          ? [h('div', { fontSize: 28, fontWeight: 600, color: color.hearth, letterSpacing: 2, textTransform: 'uppercase' }, input.kicker)]
          : []),
        h('div', { fontFamily: 'Fraunces', fontSize: titleSize, fontWeight: 500, lineHeight: 1.08, letterSpacing: -1.5 }, input.title),
      ]),
      h('div', { display: 'flex', justifyContent: 'space-between', fontSize: 28, color: color.muted, borderTop: `2px solid ${color.line}`, paddingTop: 28 }, [
        h('div', {}, 'Not about control. About being present together.'),
        h('div', { fontWeight: 600 }, site.domain),
      ]),
    ],
  );
  const svg = await satori(tree as unknown as Parameters<typeof satori>[0], { width: 1200, height: 630, fonts });
  return new Resvg(svg).render().asPng();
}

/** Square icon: the two circles on Cream. Used for the touch icon and the Organization logo. */
export function renderIcon(size: number): Uint8Array {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="${size}" height="${size}">
    <rect width="512" height="512" fill="${color.surface}"/>
    <circle cx="200" cy="256" r="128" fill="${color.hearth}"/>
    <circle cx="312" cy="256" r="128" fill="${color.glow}" fill-opacity="0.88"/>
  </svg>`;
  return new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render().asPng();
}
