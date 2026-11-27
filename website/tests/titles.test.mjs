import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { allPages, page, ROOT, textOf } from './helpers.mjs';

test('no page repeats its title as a second h1', () => {
  for (const { file, html } of allPages()) {
    const h1s = [...html.matchAll(/<h1\b[^>]*>([\s\S]*?)<\/h1>/g)].map((m) => textOf(m[1]));
    assert.equal(new Set(h1s).size, h1s.length, `${file}: ${h1s.join(' | ')}`);
  }
});

test('strip-title removes only a leading heading', () => {
  const front = '---\ntitle: "A"\n---\n';
  const cases = [
    [`${front}\n# A\n\nbody\n`, `${front}\n\nbody\n`],
    [`${front}\nintro\n\n# Later\n`],
    [`${front}\n\`\`\`bash\n# comment\n\`\`\`\n`],
    [`${front}\n## Sub\n`],
    ['# No frontmatter\n\nbody\n', '\nbody\n'],
  ];
  const file = join(mkdtempSync(join(tmpdir(), 'strip-title-')), 'doc.md');
  for (const [input, expected = input] of cases) {
    writeFileSync(file, input);
    execFileSync('bash', [join(ROOT, 'scripts/strip-title.sh'), file]);
    assert.equal(readFileSync(file, 'utf8'), expected, JSON.stringify(input));
  }
});

test('why page states 14 languages', () => {
  assert.match(textOf(page('why')), /14 languages/);
});
