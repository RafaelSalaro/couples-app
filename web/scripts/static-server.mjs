// Tiny static file server for dist/, used by the end-to-end test and Lighthouse runs.
// It applies the two rewrites from public/_redirects so /i/<token> and /approve/<token>
// behave as they will on Cloudflare Pages, and serves text files gzip-compressed.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { gzipSync } from 'node:zlib';

const types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.xml': 'application/xml',
  '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
};
const rewrites = [
  [/^\/i\/.+/, '/invite/'],
  [/^\/approve\/.+/, '/approve-request/'],
];

export function serveDist(root, port) {
  const server = createServer(async (req, res) => {
    let path = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    for (const [pattern, target] of rewrites) if (pattern.test(path)) path = target;
    let file = join(root, normalize(path));
    if (!file.startsWith(root)) {
      res.writeHead(403);
      return res.end();
    }
    try {
      if ((await stat(file)).isDirectory()) file = join(file, 'index.html');
      let body = await readFile(file);
      const ext = extname(file);
      const type = types[ext] ?? (path.startsWith('/.well-known/') ? 'application/json' : 'application/octet-stream');
      const headers = { 'Content-Type': type };
      if (path.startsWith('/_astro/')) headers['Cache-Control'] = 'public, max-age=31536000, immutable';
      if (/text|json|xml|javascript|svg/.test(type) && /gzip/.test(req.headers['accept-encoding'] ?? '')) {
        body = gzipSync(body);
        headers['Content-Encoding'] = 'gzip';
      }
      res.writeHead(200, headers);
      res.end(body);
    } catch {
      const body = await readFile(join(root, '404.html')).catch(() => 'Not found');
      res.writeHead(404, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(body);
    }
  });
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)));
}
