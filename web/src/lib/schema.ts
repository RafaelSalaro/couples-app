// Structured data builders (docs/09-website-and-seo.md §5).
// Only facts that are true today go in here: no ratings, reviews or counts
// until real ones exist.
import { site, absoluteUrl } from '../config/site';

export interface Crumb {
  name: string;
  path: string;
}

export interface FaqItem {
  question: string;
  /** Plain text answer. */
  answer: string;
}

const orgId = `${site.url}/#organization`;
const websiteId = `${site.url}/#website`;

export const organizationSchema = () => ({
  '@context': 'https://schema.org',
  '@type': 'Organization',
  '@id': orgId,
  name: site.name,
  legalName: site.company,
  url: `${site.url}/`,
  logo: absoluteUrl('/logo.png'),
  email: site.supportEmail,
});

export const websiteSchema = () => ({
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  '@id': websiteId,
  name: site.name,
  url: `${site.url}/`,
  inLanguage: 'en',
  publisher: { '@id': orgId },
});

export const breadcrumbSchema = (crumbs: Crumb[]) => ({
  '@context': 'https://schema.org',
  '@type': 'BreadcrumbList',
  itemListElement: [{ name: 'Home', path: '/' }, ...crumbs].map((crumb, index) => ({
    '@type': 'ListItem',
    position: index + 1,
    name: crumb.name,
    item: absoluteUrl(crumb.path),
  })),
});

export const faqSchema = (items: FaqItem[]) => ({
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  mainEntity: items.map((item) => ({
    '@type': 'Question',
    name: item.question,
    acceptedAnswer: { '@type': 'Answer', text: item.answer },
  })),
});

/** The app itself. Prices are for the couple: one purchase covers both partners (decision M7). */
export const appSchema = () => ({
  '@context': 'https://schema.org',
  '@type': 'MobileApplication',
  '@id': `${site.url}/#app`,
  name: site.name,
  description: site.description,
  url: `${site.url}/`,
  applicationCategory: 'LifestyleApplication',
  operatingSystem: 'iOS 17 or later',
  publisher: { '@id': orgId },
  ...(site.launched && site.appStoreUrl ? { downloadUrl: site.appStoreUrl } : {}),
  offers: [
    {
      '@type': 'Offer',
      name: 'Free',
      price: '0',
      priceCurrency: site.pricing.currency,
    },
    {
      '@type': 'Offer',
      name: 'Premium yearly, one price for both partners',
      description: `One subscription covers both partners. ${site.pricing.trialDays}-day free trial.`,
      price: site.pricing.yearly,
      priceCurrency: site.pricing.currency,
    },
    {
      '@type': 'Offer',
      name: 'Premium lifetime, one price for both partners',
      description: 'One purchase covers both partners.',
      price: site.pricing.lifetime,
      priceCurrency: site.pricing.currency,
    },
  ],
});

export const articleSchema = (article: {
  title: string;
  description: string;
  path: string;
  published: Date;
  updated?: Date;
  og: string;
}) => ({
  '@context': 'https://schema.org',
  '@type': 'Article',
  headline: article.title,
  description: article.description,
  image: absoluteUrl(`/og/${article.og}.png`),
  datePublished: article.published.toISOString(),
  dateModified: (article.updated ?? article.published).toISOString(),
  inLanguage: 'en',
  mainEntityOfPage: absoluteUrl(article.path),
  author: { '@type': 'Organization', '@id': orgId, name: site.name, url: `${site.url}/about/` },
  publisher: { '@id': orgId },
});
