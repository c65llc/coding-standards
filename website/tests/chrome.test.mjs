// Header wordmark, shared footer and default theme.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import vm from 'node:vm';
import { allPages, DIST, page, textOf } from './helpers.mjs';

const footers = (html) => html.match(/<footer\b[^>]*class="[^"]*\bsite-footer\b[\s\S]*?<\/footer>/g) ?? [];
// The homepage gets the footer with its redesign.
const footerPages = () => allPages().filter(({ file }) => file !== 'index.html');

test('every page has one C65 footer', () => {
  const pages = footerPages();
  assert.ok(pages.some(({ file }) => file === '404.html'));
  for (const { file, html } of pages) {
    const found = footers(html);
    assert.equal(found.length, 1, `${file}: ${found.length} footers`);
    const [footer] = found;
    assert.match(footer, /<a\b[^>]*href="https:\/\/www\.c65llc\.com\/"[^>]*>\s*<svg\b[^>]*role="img"[^>]*aria-label="C65"/, file);
    for (const href of ['/getting-started/quick-start/', '/blog/', '/rss.xml', 'https://github.com/c65llc/coding-standards']) {
      assert.ok(footer.includes(`href="${href}"`), `${file}: footer lacks ${href}`);
    }
    assert.match(textOf(footer), /a C65 project/, file);
    assert.match(textOf(footer), /© \d{4} C65 LLC/, file);
  }
});

test('docs pages keep their previous/next links', () => {
  assert.match(page('getting-started/installation'), /rel="(next|prev)"/);
});

test('docs header shows the wordmark', () => {
  assert.match(page('getting-started/installation'), /<a\b[^>]*class="[^"]*\bwordmark\b/);
});

function seedScript(html) {
  const head = html.slice(0, html.indexOf('</head>'));
  const scripts = [...head.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  const seed = scripts.findIndex((body) => body.includes('starlight-theme') && body.includes('setItem'));
  const starlight = scripts.findIndex((body) => body.includes('prefers-color-scheme') && body.includes('dataset.theme'));
  assert.notEqual(seed, -1, 'no theme seed script in <head>');
  assert.notEqual(starlight, -1, 'no Starlight theme script in <head>');
  assert.ok(seed < starlight, 'seed script must run before Starlight reads the theme');
  return scripts[seed];
}

function run(script, getItem) {
  const writes = [];
  vm.runInNewContext(script, { localStorage: { getItem, setItem: (...args) => writes.push(args) } });
  return writes;
}

test('a first visit is seeded as dark', () => {
  const script = seedScript(page('getting-started/installation'));
  assert.deepEqual(run(script, () => null), [['starlight-theme', 'dark']]);
});

test('an existing choice is left alone', () => {
  const script = seedScript(page('getting-started/installation'));
  // '' is how Starlight stores Auto.
  for (const stored of ['', 'light', 'dark']) assert.deepEqual(run(script, () => stored), []);
});

test('blocked storage does not throw', () => {
  const script = seedScript(page('getting-started/installation'));
  assert.doesNotThrow(() => run(script, () => { throw new Error('denied'); }));
});

test('the built CSP covers the seed script', () => {
  assert.match(readFileSync(join(DIST, '_headers'), 'utf8'), /script-src 'self' 'wasm-unsafe-eval' 'sha256-/);
});
