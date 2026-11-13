# 09 — Website and SEO

## 1. Purpose

1. Present the app beautifully and convert visitors (waitlist before launch, App Store and Google Play after).
2. Earn search traffic around couples, phones and connection.
3. Host what the apps need: invite universal links, privacy policy, terms, support, account-deletion help, the Android-partner web approval page, press kit.

## 2. Stack

- **Astro** static site, TypeScript, content collections for guides/blog in Markdown.
- Styling with plain CSS using the design tokens from `10-brand-and-design-system.md` (CSS custom properties, light and dark).
- Animation: CSS and the View Transitions API first; a small library (Motion One) only where needed. No heavy animation frameworks. Every animation respects `prefers-reduced-motion`.
- **Hosting:** Cloudflare Pages (free), custom domain, HTTPS, automatic preview deploys per branch.
- **Forms:** waitlist posts to the `waitlist_join` Edge Function; Resend sends double opt-in.
- **Analytics:** Cloudflare Web Analytics (free, cookieless, no consent banner needed) plus Google Search Console and Bing Webmaster Tools.
- Performance budget: Lighthouse 95+ on all four scores; Largest Contentful Paint < 2.0 s on mobile; total JavaScript < 50 KB on the home page.

## 3. Site map

| Path | Purpose |
|---|---|
| `/` | Home (sections in §4) |
| `/how-it-works` | The three unlock methods and minutes in depth |
| `/pricing` | Free vs premium, prices shown as one price for both partners ($39.99/year or $119.99 lifetime for the couple, about $20 per person), FAQ |
| `/guides/` | SEO content hub (articles) |
| `/about` | The philosophy and the founder's story |
| `/support` | Help center, contact, account deletion steps |
| `/safety` | Safety by design, relationship-safety resources |
| `/privacy`, `/terms` | Legal (required by both stores) |
| `/press` | Logo, screenshots, one-paragraph description |
| `/i/<token>` | Invite landing (universal link fallback) |
| `/approve/<token>` | Web approval for partners without the app |
| `/.well-known/apple-app-site-association`, `/.well-known/assetlinks.json` | Deep-link files |

## 4. Home page sections

1. **Hero:** tagline ("Less scrolling. More us."), one sentence, animated phone showing protected time turning into a kudos moment, primary button (waitlist, later store badges).
2. **Philosophy:** "Not about control. About being intentional and present together."
3. **How it works:** three cards — scan, ask, earn — each with a small looping animation.
4. **The kudos moment:** an animated notification "Ana says you made her laugh · +10 min".
5. **Protected time:** the 6 PM–9 AM default explained as "evenings and mornings back".
6. **Shared progress:** streak and weekly report preview.
7. **Privacy promise:** "Your partner never sees your apps, messages or location."
8. **Pricing teaser:** "One price for both of you — $39.99 a year." Prices on the site always say they cover both partners.
9. **FAQ** (also marked up for search).
10. **Footer:** guides, support, safety, privacy, terms, press.

## 5. Technical SEO checklist

- Unique `<title>` and meta description per page; one H1; semantic headings.
- Open Graph and Twitter card images per page (generated at build time in brand style).
- Structured data: `SoftwareApplication`/`MobileApplication` (name, operating system, offers, rating once available), `FAQPage`, `Organization`, `Article` for guides, `BreadcrumbList`.
- `sitemap.xml` (Astro sitemap integration) and `robots.txt`; submit to Search Console and Bing.
- Canonical URLs; clean slugs; internal links from every guide to `/how-it-works` and `/pricing`.
- Smart App Banner meta tag after launch; App Store and Google Play badges.
- Image formats AVIF/WebP with explicit width and height; lazy-load below the fold.
- `hreflang` ready for Portuguese (Brazil) later.

## 6. Keyword strategy (initial targets)

| Cluster | Example queries | Page type |
|---|---|---|
| Product | app blocker for couples, screen time app for couples, block social media together | Home, How it works |
| Problem | partner always on phone, phone addiction relationship, phubbing in relationships | Guides |
| Ideas | phone-free date ideas, things to do together without phones, evening routine for couples | Guides (high volume, top of funnel) |
| Comparison | Opal alternative for couples, One Sec vs, Paired app alternative | Comparison guides (fair, factual) |
| How-to | how to reduce screen time together, how to block Instagram at night iPhone | Guides with app screenshots |

Validate volumes in Google Search Console after 4–6 weeks of data and adjust.

## 7. Content plan

- **Pre-launch (start now with the waitlist):** 6 cornerstone guides — phone-free date ideas, phubbing explained, evening routine for couples, how to block social media at night on iPhone, screen time agreements for couples, the science of attention and relationships (cite sources).
- **Ongoing:** 1 new guide per week, plus refreshing one older guide per month.
- Each guide: 1,200–2,000 words, practical, original photos or illustrations in brand style, a soft call to action, author and date, FAQ block.

## 8. Weekly SEO routine (every Monday, about 60 minutes)

1. **Search Console review:** queries gaining impressions, pages with high impressions and low click rate (rewrite titles/descriptions), any indexing or Core Web Vitals errors.
2. **Rankings snapshot:** track the 20 target queries in a sheet (Search Console average position).
3. **Publish** the week's new guide; add internal links from 2 older guides.
4. **Refresh** one underperforming page (title, intro, FAQ).
5. **Technical check:** Lighthouse on home and newest guide; broken-link check.
6. **Off-site:** one outreach action (podcast, couples blogger, relationship therapist newsletter, Reddit/community answer that genuinely helps).
7. **App Store Optimization (after launch):** review App Store Connect search terms and conversion; adjust keywords field monthly.
8. Log results in the SEO tracker sheet.

This routine can be automated as a weekly scheduled task that drafts the Search Console summary and next guide outline for review.

## 9. Build order

1. Week 1: waitlist landing page (hero, philosophy, how it works, waitlist form), privacy and terms drafts, deep-link files.
2. Weeks 2–4: full site sections, first 6 guides, Search Console setup.
3. Before launch: pricing page with real prices, press kit, store badges, support center.
