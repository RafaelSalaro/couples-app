// Deep-link files (docs/09 §3, docs/06 §9), generated from the site config so the
// bundle ID and team ID live in one place.
//   /.well-known/apple-app-site-association  (no extension, served as JSON via public/_headers)
//   /.well-known/assetlinks.json
import type { APIRoute, GetStaticPaths } from 'astro';
import { site } from '../config/site';

const appleAppSiteAssociation = {
  applinks: {
    details: [
      {
        appIDs: [`${site.appleTeamId}.${site.iosBundleId}`],
        // Invite links open the app; everything else stays on the website.
        components: [{ '/': '/i/*', comment: 'Partner invite links' }],
      },
    ],
  },
};

// Android is not built yet (docs/08). The file exists so the path is reserved;
// add the package name and signing certificate fingerprint when the Android app has them.
const assetLinks: unknown[] = [];

const files: Record<string, unknown> = {
  '.well-known/apple-app-site-association': appleAppSiteAssociation,
  '.well-known/assetlinks.json': assetLinks,
};

export const getStaticPaths: GetStaticPaths = () =>
  Object.keys(files).map((deeplink) => ({ params: { deeplink } }));

export const GET: APIRoute = ({ params }) =>
  new Response(JSON.stringify(files[params.deeplink as string], null, 2), {
    headers: { 'Content-Type': 'application/json' },
  });
