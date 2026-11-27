import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { basename, join } from 'node:path';
import test from 'node:test';
import { distFiles, ROOT } from './helpers.mjs';

const EXPECTED = {
  //            dark       light
  bg: ['#1f1b19', '#f6efe6'],
  panel: ['#2a2522', '#fffaf3'],
  footer: ['#171412', '#2d2926'],
  heading: ['#f6efe6', '#2d2926'],
  text: ['#c4b5a6', '#54483f'],
  accent: ['#e8935f', '#8d4021'],
  rule: ['#453c36', '#cdb9a6'],
};

function tokens(selector) {
  const css = readFileSync(join(ROOT, 'src/styles/tokens.css'), 'utf8');
  const start = css.indexOf(`${selector} {`);
  assert.notEqual(start, -1, `tokens.css has no "${selector}" block`);
  const block = css.slice(start, css.indexOf('}', start));
  return Object.fromEntries([...block.matchAll(/--cs-([a-z-]+):\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
}

function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

const themes = { dark: () => tokens(':root'), light: () => ({ ...tokens(':root'), ...tokens(":root[data-theme='light']") }) };

for (const [index, [name, load]] of Object.entries(themes).entries()) {
  test(`${name} tokens match the spec`, () => {
    const t = load();
    for (const [key, values] of Object.entries(EXPECTED)) assert.equal(t[key], values[index], `--cs-${key}`);
  });

  test(`${name} text meets WCAG AA`, () => {
    const t = load();
    const pairs = ['text', 'heading', 'accent'].flatMap((fg) => [[fg, 'bg'], [fg, 'panel']]);
    pairs.push(['footer-text', 'footer'], ['ember', 'footer']);
    for (const [fg, bg] of pairs) {
      const ratio = contrast(t[fg], t[bg]);
      assert.ok(ratio >= 4.5, `--cs-${fg} on --cs-${bg}: ${ratio.toFixed(2)}`);
    }
  });
}

test('fonts are self-hosted', () => {
  for (const file of [...distFiles('.html'), ...distFiles('.css')]) {
    assert.doesNotMatch(readFileSync(file, 'utf8'), /fonts\.(googleapis|gstatic)\.com/, file);
  }
  const fonts = distFiles('.woff2').map((file) => basename(file));
  for (const family of ['figtree', 'jetbrains-mono']) {
    assert.ok(fonts.some((name) => name.startsWith(family)), `no ${family} woff2 in dist`);
  }
});

test('docs pages load the theme', () => {
  const css = distFiles('.css').map((file) => readFileSync(file, 'utf8')).join('\n');
  assert.match(css, /--sl-color-bg:\s*var\(--cs-bg\)/);
});
