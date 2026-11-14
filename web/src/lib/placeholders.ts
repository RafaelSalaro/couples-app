// Shared Markdown (content/legal/*.md, also used outside the website) refers to the brand
// through tokens such as {{APP_NAME}}, because the name, company and domain are not final.
// The website fills them in from the site config at build time (see LegalPage.astro).
import { site } from '../config/site';

export const placeholderValues: Record<string, string> = {
  APP_NAME: site.name,
  COMPANY: site.company,
  DOMAIN: site.domain,
  SUPPORT_EMAIL: site.supportEmail,
  PRIVACY_EMAIL: site.privacyEmail,
};

export const fillPlaceholders = (text: string): string =>
  text.replace(/\{\{([A-Z_]+)\}\}/g, (match, key: string) => placeholderValues[key] ?? match);

/** Fills tokens in rendered HTML, including tokens that were URL-encoded inside link targets. */
export const fillPlaceholdersInHtml = (html: string): string =>
  fillPlaceholders(html.replace(/%7B%7B([A-Z_]+)%7D%7D/g, '{{$1}}'));
