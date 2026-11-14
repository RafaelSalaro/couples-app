// Navigation in one place. Every href must point to a page that exists
// (scripts/check-site.mjs fails the build on broken internal links).

export const headerNav = [
  { href: '/how-it-works/', label: 'How it works' },
  { href: '/pricing/', label: 'Pricing' },
  { href: '/guides/', label: 'Guides' },
  { href: '/about/', label: 'About' },
];

export const footerNav = [
  {
    title: 'Product',
    links: [
      { href: '/how-it-works/', label: 'How it works' },
      { href: '/pricing/', label: 'Pricing' },
      { href: '/guides/', label: 'Guides' },
      { href: '/about/', label: 'About' },
    ],
  },
  {
    title: 'Help',
    links: [
      { href: '/support/', label: 'Support' },
      { href: '/safety/', label: 'Safety' },
      { href: '/press/', label: 'Press' },
    ],
  },
  {
    title: 'Legal',
    links: [
      { href: '/privacy/', label: 'Privacy' },
      { href: '/terms/', label: 'Terms' },
    ],
  },
];
