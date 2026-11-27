import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { page, ROOT, textOf } from './helpers.mjs';

const home = () => page('');
const section = (id) => {
  const match = home().match(new RegExp(`<section\\b[^>]*id="${id}"[\\s\\S]*?</section>`));
  assert.ok(match, `no section#${id}`);
  return match[0];
};
const has = (haystack, needles) => {
  for (const needle of needles) assert.ok(haystack.includes(needle), `missing: ${needle}`);
};

test('hero headline, lead and dark theme', () => {
  const html = home();
  assert.match(html, /<html\b[^>]*data-theme="dark"/);
  assert.equal(textOf(html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/)[1]), 'Write the rule once.');
  has(textOf(html), ['One set of coding standards, compiled into the file each AI agent already reads.']);
});

test('header links', () => {
  const header = home().match(/<header\b[\s\S]*?<\/header>/)[0];
  has(header, ['class="wordmark', 'href="/getting-started/quick-start/"', 'href="/blog/"', 'href="#usage"',
    'href="https://github.com/c65llc/coding-standards"', 'href="/rss.xml"']);
});

test('the install command appears in the hero and the closing call', () => {
  const command = 'curl -fsSL https://raw.githubusercontent.com/c65llc/coding-standards/main/install.sh | bash';
  assert.equal(textOf(home()).split(command).length - 1, 2);
});

test('source panel quotes a rule that is copied into configs, with its line numbers', () => {
  const lines = readFileSync(join(ROOT, '../standards/shared/blocks/architecture-core.md'), 'utf8').split('\n');
  const start = lines.findIndex((line) => line.startsWith('Validate inputs at boundaries.'));
  assert.notEqual(start, -1);
  const text = textOf(section('compile'));
  has(text, ['standards/shared/blocks/architecture-core.md']);
  for (let i = start; i < start + 3; i += 1) has(text, [`${i + 1} ${lines[i]}`]);
});

test('output tree lists all six agent files', () => {
  has(textOf(section('compile')), ['CLAUDE.md', 'AGENTS.md', '.cursorrules', '.github/copilot-instructions.md',
    '.gemini/GEMINI.md', '.aider-instructions.md']);
});

test('why section', () => {
  const why = section('why');
  const lines = (cls) => [...why.matchAll(new RegExp(`<div\\b[^>]*class="${cls}\\b[^"]*"[^>]*>([\\s\\S]*?)</div>`, 'g'))].map((m) => textOf(m[1]));
  for (const [cls, mark] of [['del', '-'], ['add', '+']]) {
    assert.equal(lines(cls).length, 3);
    assert.ok(lines(cls).every((line) => line.startsWith(`${mark} `)));
  }
  has(textOf(why), ['Why coding standards?', '// sync', '// architecture', '// setup', '// updates', '14 languages',
    'Customized agent configs are never overwritten']);
  has(why, ['href="/why/"']);
});

test('all 14 languages', () => {
  const items = [...section('languages').matchAll(/<li\b[^>]*>([\s\S]*?)<\/li>/g)].map((m) => textOf(m[1]));
  assert.deepEqual(items, ['Python', 'Java', 'Kotlin', 'Swift', 'Dart', 'TypeScript', 'JavaScript', 'Rust', 'Zig', 'Ruby',
    'Ruby on Rails', 'Go', 'Elixir', 'C++']);
});

test('usage keeps its five apps and links', () => {
  has(section('usage'), ['https://sostalog.com', 'https://dopotasks.com', 'https://pigeonpile.com/apps/wiki',
    'https://sprigedit.com', 'https://awayteamapp.com', 'href="https://www.c65llc.com"', 'href="https://pigeonpile.com"']);
});

test('copy buttons stay hidden until script enables them', () => {
  const buttons = home().match(/<button\b[^>]*>/g) ?? [];
  assert.equal(buttons.length, 2);
  for (const button of buttons) assert.match(button, /\shidden(\s|>|=)/);
});

test('outdated copy is gone', () => {
  assert.doesNotMatch(textOf(home()), /The Problem|six leading/);
});

test('head metadata survives', () => {
  has(home(), ['property="og:title"', 'property="og:description"', 'property="og:image"', 'rel="sitemap"',
    'type="application/rss+xml"']);
});
