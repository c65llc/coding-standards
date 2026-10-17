#!/usr/bin/env node
/**
 * csp-postbuild.mjs — finish the Content-Security-Policy after `astro build`.
 *
 * Starlight ships a handful of inline <script> tags (theme provider, sidebar
 * state, search shortcut) and thousands of inline `style="--0:…"` attributes
 * (Expressive Code token colours, sidebar depth). Allowing them with
 * 'unsafe-inline' defeats the point of a CSP, so this step hashes them instead:
 *
 *  1. `dist/_headers` (the Cloudflare Pages header file, copied from public/)
 *     is a template. The placeholders `__CSP_SCRIPT_HASHES__` and
 *     `__CSP_STYLE_HASHES__` are replaced with the de-duplicated SHA-256 hashes
 *     of every executable inline <script> / inline <style> found in dist/**.html.
 *     The header is one policy for the whole site, so it carries the union.
 *
 *  2. Inline `style` attributes are too numerous for the header (Cloudflare
 *     caps a _headers line at 2,000 characters) and the header therefore keeps
 *     `style-src-attr 'unsafe-inline'`. Each page gets a
 *     <meta http-equiv="Content-Security-Policy"> carrying
 *     `style-src-attr 'unsafe-hashes' <hashes of that page's style attrs>`.
 *     Browsers enforce every delivered policy, so the effective policy is the
 *     intersection: only the exact attribute values present on the page.
 *
 * The step fails the build if the policy could not be made hash-based (inline
 * event handlers, missing placeholders) or if the header exceeds the Cloudflare
 * limit, so a Starlight upgrade that introduces new inline content is caught
 * in CI rather than as a broken deploy.
 *
 * Usage: node scripts/csp-postbuild.mjs [--dist <dir>]   (default: ../dist)
 */

import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const CLOUDFLARE_HEADERS_LINE_LIMIT = 2000;
const SCRIPT_PLACEHOLDER = '__CSP_SCRIPT_HASHES__';
const STYLE_PLACEHOLDER = '__CSP_STYLE_HASHES__';
const META_MARKER = '<meta http-equiv="Content-Security-Policy" content="style-src-attr ';

// Script types that the browser executes and therefore checks against
// script-src. Anything else (application/ld+json, application/json, …) is a
// data block the CSP never evaluates.
const EXECUTABLE_SCRIPT_TYPES = new Set([
  '',
  'module',
  'text/javascript',
  'application/javascript',
  'text/ecmascript',
  'application/ecmascript',
  'importmap',
  'speculationrules',
]);

function parseArgs(argv) {
  const scriptDir = dirname(fileURLToPath(import.meta.url));
  let dist = resolve(scriptDir, '..', 'dist');
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--dist' && argv[i + 1]) {
      dist = resolve(argv[i + 1]);
      i += 1;
    } else {
      throw new Error(`Unknown argument: ${argv[i]}`);
    }
  }
  return { dist };
}

function walkHtml(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) walkHtml(full, out);
    else if (entry.name.endsWith('.html')) out.push(full);
  }
  return out;
}

function cspHash(content) {
  return `'sha256-${createHash('sha256').update(content, 'utf8').digest('base64')}'`;
}

function attrValue(attrs, name) {
  const match = new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'>]+))`, 'i').exec(attrs);
  if (!match) return undefined;
  return match[1] ?? match[2] ?? match[3] ?? '';
}

function hasAttr(attrs, name) {
  return new RegExp(`\\s${name}(?:\\s|=|$)`, 'i').test(attrs);
}

const NAMED_ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

// Browsers hash the attribute's *decoded* value, so undo HTML attribute escaping.
function decodeEntities(text) {
  return text.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (whole, body) => {
    if (body[0] === '#') {
      const code = body[1].toLowerCase() === 'x' ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      return Number.isNaN(code) ? whole : String.fromCodePoint(code);
    }
    return NAMED_ENTITIES[body.toLowerCase()] ?? whole;
  });
}

/** Collect the inline content a CSP would evaluate on one page. */
function scanPage(html, file) {
  const scripts = new Set();
  const styles = new Set();
  const styleAttrs = new Set();
  const problems = [];

  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)) {
    const [, attrs, body] = match;
    if (hasAttr(attrs, 'src')) continue; // external, covered by 'self'
    const type = (attrValue(attrs, 'type') ?? '').trim().toLowerCase();
    if (!EXECUTABLE_SCRIPT_TYPES.has(type)) continue; // data block
    scripts.add(cspHash(body));
  }

  for (const match of html.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style\s*>/gi)) {
    styles.add(cspHash(match[1]));
  }

  // Inline style attributes and inline event handlers live on arbitrary tags.
  for (const match of html.matchAll(/<[a-z][a-z0-9-]*(\s[^>]*)>/gi)) {
    const attrs = match[1];
    const style = attrValue(attrs, 'style');
    if (style !== undefined) styleAttrs.add(cspHash(decodeEntities(style)));
    const handler = /\s(on[a-z]+)\s*=/i.exec(attrs);
    if (handler) {
      problems.push(`${file}: inline event handler ${handler[1]} cannot be allowed by a hash-based CSP`);
    }
  }

  return { scripts, styles, styleAttrs, problems };
}

function injectMeta(html, styleAttrs) {
  const sources = styleAttrs.size > 0 ? `'unsafe-hashes' ${[...styleAttrs].sort().join(' ')}` : "'none'";
  const meta = `${META_MARKER}${sources}">`;
  // Idempotent: replace a meta tag we injected on a previous run.
  const existing = new RegExp(`${META_MARKER.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[^"]*">`);
  if (existing.test(html)) return html.replace(existing, meta);
  const head = /<head(?:\s[^>]*)?>/i.exec(html);
  if (!head) throw new Error('page has no <head> to carry the CSP meta tag');
  const at = head.index + head[0].length;
  return html.slice(0, at) + meta + html.slice(at);
}

/** Substitute the placeholders on one `Content-Security-Policy:` header line and validate it. */
function renderCspLine(line, scriptHashes, styleHashes) {
  if (!line.includes(SCRIPT_PLACEHOLDER) || !line.includes(STYLE_PLACEHOLDER)) {
    throw new Error(
      `the Content-Security-Policy line in _headers must contain ${SCRIPT_PLACEHOLDER} and ` +
        `${STYLE_PLACEHOLDER} (already rendered? re-run \`astro build\`); without them the inline hashes never ship`,
    );
  }
  const rendered = line
    .replace(SCRIPT_PLACEHOLDER, [...scriptHashes].sort().join(' '))
    .replace(STYLE_PLACEHOLDER, [...styleHashes].sort().join(' '))
    // Collapse the gap left by an empty hash list ("'self' ;" -> "'self';").
    .replace(/ +;/g, ';')
    .replace(/ +$/, '');

  if (rendered.length > CLOUDFLARE_HEADERS_LINE_LIMIT) {
    throw new Error(
      `Content-Security-Policy header is ${rendered.length} chars; Cloudflare Pages caps a _headers ` +
        `line at ${CLOUDFLARE_HEADERS_LINE_LIMIT}. Reduce inline scripts/styles or move the policy to a Pages Function.`,
    );
  }
  const scriptSrc = /script-src\s[^;]*/i.exec(rendered)?.[0] ?? '';
  const styleSrc = /style-src\s[^;]*/i.exec(rendered)?.[0] ?? '';
  if (/'unsafe-inline'/.test(scriptSrc) || /'unsafe-inline'/.test(styleSrc)) {
    throw new Error("script-src / style-src must not contain 'unsafe-inline' — use the hash placeholders");
  }
  return rendered;
}

/** Render the _headers template: only `Content-Security-Policy:` lines change; comments and other headers are kept verbatim. */
function renderHeaders(template, scriptHashes, styleHashes) {
  let cspLength = 0;
  let cspLines = 0;
  const rendered = template
    .split('\n')
    .map((line) => {
      if (!/^\s*Content-Security-Policy:/i.test(line)) return line;
      cspLines += 1;
      const out = renderCspLine(line, scriptHashes, styleHashes);
      cspLength = Math.max(cspLength, out.length);
      return out;
    })
    .join('\n');
  if (cspLines === 0) {
    throw new Error('_headers has no Content-Security-Policy line to render');
  }
  return { rendered, cspLength };
}

function main() {
  const { dist } = parseArgs(process.argv.slice(2));
  const headersPath = join(dist, '_headers');
  const template = readFileSync(headersPath, 'utf8');
  const pages = walkHtml(dist);

  const siteScripts = new Set();
  const siteStyles = new Set();
  const siteStyleAttrs = new Set();
  const problems = [];

  for (const file of pages) {
    const html = readFileSync(file, 'utf8');
    const page = scanPage(html, file);
    problems.push(...page.problems);
    for (const h of page.scripts) siteScripts.add(h);
    for (const h of page.styles) siteStyles.add(h);
    for (const h of page.styleAttrs) siteStyleAttrs.add(h);
    const updated = injectMeta(html, page.styleAttrs);
    if (updated !== html) writeFileSync(file, updated);
  }

  if (problems.length > 0) {
    throw new Error(`CSP cannot be hash-based:\n  ${problems.join('\n  ')}`);
  }

  const { rendered, cspLength } = renderHeaders(template, siteScripts, siteStyles);
  writeFileSync(headersPath, rendered);

  console.log(
    `[csp-postbuild] ${pages.length} page(s): ${siteScripts.size} inline script hash(es), ` +
      `${siteStyles.size} inline style hash(es) in _headers (CSP line ${cspLength}/${CLOUDFLARE_HEADERS_LINE_LIMIT} chars); ` +
      `${siteStyleAttrs.size} distinct style attribute hash(es) across per-page meta tags.`,
  );
}

try {
  main();
} catch (error) {
  console.error(`[csp-postbuild] ${error.message}`);
  process.exit(1);
}
