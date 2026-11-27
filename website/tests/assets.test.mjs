import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { ROOT } from './helpers.mjs';

test('favicon uses the new colours', () => {
  const svg = readFileSync(join(ROOT, 'public/favicon.svg'), 'utf8');
  assert.match(svg, /#e8935f/);
  assert.match(svg, /#1f1b19/);
  assert.doesNotMatch(svg, /#1a1a2e/);
});

test('social image is 1200x630', () => {
  const png = readFileSync(join(ROOT, 'public/og-image.png'));
  assert.deepEqual([png.readUInt32BE(16), png.readUInt32BE(20)], [1200, 630]);
});
