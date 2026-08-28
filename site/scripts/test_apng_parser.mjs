#!/usr/bin/env node

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseApng } from './lib/apng.mjs';

const animationPath = fileURLToPath(new URL('../../docs/assets/notifications-macos.apng', import.meta.url));
const animation = await readFile(animationPath);

/** Find a complete PNG chunk by type for deterministic corruption tests. */
function findChunk(buffer, expectedType) {
  let cursor = 8;
  while (cursor + 12 <= buffer.length) {
    const length = buffer.readUInt32BE(cursor);
    const type = buffer.subarray(cursor + 4, cursor + 8).toString('ascii');
    if (type === expectedType) return { cursor, length, end: cursor + length + 12 };
    cursor += length + 12;
  }
  throw new Error(`Fixture is missing ${expectedType}.`);
}

test('accepts the observed single-play APNG', () => {
  const parsed = parseApng(animation, 'fixture');
  assert.ok(parsed.frames >= 3);
  assert.equal(parsed.plays, 1);
  assert.ok(parsed.durationMilliseconds > 0);
});

test('rejects a chunk truncated before its CRC ends', () => {
  assert.throws(() => parseApng(animation.subarray(0, -1), 'fixture'), /truncated/);
});

test('rejects a missing IEND chunk', () => {
  const iend = findChunk(animation, 'IEND');
  assert.throws(() => parseApng(animation.subarray(0, iend.cursor), 'fixture'), /missing IEND/);
});

test('rejects a non-zero IEND payload', () => {
  const iend = findChunk(animation, 'IEND');
  const invalidIend = Buffer.alloc(13);
  invalidIend.writeUInt32BE(1, 0);
  invalidIend.write('IEND', 4, 'ascii');
  assert.throws(
    () => parseApng(Buffer.concat([animation.subarray(0, iend.cursor), invalidIend]), 'fixture'),
    /invalid IEND chunk/,
  );
});

test('rejects an invalid PNG signature', () => {
  const invalid = Buffer.from(animation);
  invalid[0] = 0;
  assert.throws(() => parseApng(invalid, 'fixture'), /invalid PNG signature/);
});

test('rejects incomplete animation frame control', () => {
  const invalid = Buffer.from(animation);
  const control = findChunk(invalid, 'acTL');
  invalid.writeUInt32BE(invalid.readUInt32BE(control.cursor + 8) + 1, control.cursor + 8);
  assert.throws(() => parseApng(invalid, 'fixture'), /frame mismatch/);
});
