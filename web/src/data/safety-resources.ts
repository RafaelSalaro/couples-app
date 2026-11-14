// Relationship-safety resources shown on /safety/ (docs/11-business-legal-launch.md §5,
// docs/03-feature-spec.md §16). United States only for now.
// FOUNDER: confirm every phone number and link before launch, and again every few months.
// Add resources for other countries before the app is offered there.
export interface SafetyResource {
  name: string;
  description: string;
  phone?: { label: string; href: string };
  text?: string;
  url: string;
  urlLabel: string;
}

export const safetyResources: SafetyResource[] = [
  {
    name: 'National Domestic Violence Hotline (US)',
    description: 'Free, confidential support at any hour, every day of the year, by phone, text or online chat.',
    phone: { label: '1-800-799-7233', href: 'tel:+18007997233' },
    text: 'Text START to 88788',
    url: 'https://www.thehotline.org/',
    urlLabel: 'thehotline.org',
  },
  {
    name: 'love is respect (US)',
    description: 'Support and information about healthy relationships for young people, by phone, text or online chat.',
    phone: { label: '1-866-331-9474', href: 'tel:+18663319474' },
    text: 'Text LOVEIS to 22522',
    url: 'https://www.loveisrespect.org/',
    urlLabel: 'loveisrespect.org',
  },
];
