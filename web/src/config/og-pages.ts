// One Open Graph image per page: /og/<slug>.png. Guides add theirs from the content collection.
import { site } from './site';

export const ogPages: Record<string, { title: string; kicker?: string }> = {
  default: { title: site.tagline },
  home: { title: site.tagline, kicker: 'Protected time for couples' },
  'how-it-works': { title: 'Three warm ways to unlock time together', kicker: 'How it works' },
  pricing: { title: 'One price for both of you', kicker: 'Pricing' },
  guides: { title: 'Guides for less scrolling and more us', kicker: 'Guides' },
  about: { title: 'Not about control. About being here, together.', kicker: 'About' },
  support: { title: 'We are here to help', kicker: 'Support' },
  safety: { title: 'Safety by design', kicker: 'Safety' },
  privacy: { title: 'Privacy policy', kicker: 'Legal' },
  terms: { title: 'Terms of service', kicker: 'Legal' },
  press: { title: 'Press kit', kicker: 'Press' },
};
