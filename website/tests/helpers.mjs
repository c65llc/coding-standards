// Helpers for tests that read the built site in dist/ (run `npm run build` first).
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = fileURLToPath(new URL('..', import.meta.url));
export const DIST = join(ROOT, 'dist');

export function distFiles(extension, dir = DIST) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) return distFiles(extension, full);
    return entry.name.endsWith(extension) ? [full] : [];
  });
}

/** HTML of one route; '' is the homepage. */
export function page(route) {
  return readFileSync(join(DIST, route, 'index.html'), 'utf8');
}

export function allPages() {
  return distFiles('.html').map((file) => ({ file: relative(DIST, file), html: readFileSync(file, 'utf8') }));
}

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', copy: '©', mdash: '—', rarr: '→' };

export function textOf(html) {
  return html
    .replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (whole, body) => {
      if (body[0] !== '#') return ENTITIES[body.toLowerCase()] ?? whole;
      const code = body[1].toLowerCase() === 'x' ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      return String.fromCodePoint(code);
    })
    .replace(/\s+/g, ' ')
    .trim();
}
