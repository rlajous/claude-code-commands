#!/usr/bin/env node

import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import sharp from 'sharp';
import { parseApng } from './lib/apng.mjs';

const siteRoot = fileURLToPath(new URL('../', import.meta.url));
const repoRoot = resolve(siteRoot, '..');
const assetRoot = resolve(repoRoot, 'docs/assets');
const filenames = [
  'agent-finished-macos.png',
  'pr-changes-requested-macos.png',
  'pr-approved-macos.png',
];

for (const filename of filenames) {
  const { data, info } = await sharp(resolve(assetRoot, filename))
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  if (info.width !== 720 || info.height !== 160 || info.channels !== 4) {
    throw new Error(`${filename} must be a 720x160 RGBA capture.`);
  }
  const corners = [
    data[3],
    data[((info.width - 1) * 4) + 3],
    data[(((info.height - 1) * info.width) * 4) + 3],
    data[((((info.height - 1) * info.width) + info.width - 1) * 4) + 3],
  ];
  if (corners.some((alpha) => alpha > 3)) {
    throw new Error(`${filename} contains a non-transparent corner.`);
  }
  let transparentPixels = 0;
  let opaquePixels = 0;
  for (let offset = 3; offset < data.length; offset += 4) {
    if (data[offset] <= 3) transparentPixels += 1;
    if (data[offset] >= 252) opaquePixels += 1;
  }
  const pixelCount = info.width * info.height;
  if (transparentPixels / pixelCount < 0.02 || opaquePixels / pixelCount < 0.2) {
    throw new Error(`${filename} has implausible alpha coverage.`);
  }
}

const animationPath = resolve(assetRoot, 'notifications-macos.apng');
const animation = await readFile(animationPath);
const animationStats = await stat(animationPath);
const {
  frames: frameCount,
  plays,
  durationMilliseconds,
} = parseApng(animation, 'notifications-macos.apng');
if (frameCount < 3 || plays !== 1) {
  throw new Error(`notifications-macos.apng must play one ${frameCount}-frame sequence; plays=${plays}.`);
}
if (durationMilliseconds <= 0 || durationMilliseconds >= 5_000) {
  throw new Error(`notifications-macos.apng duration must be below five seconds; got ${durationMilliseconds}ms.`);
}
if (animationStats.size > 1024 * 1024) {
  throw new Error(`notifications-macos.apng exceeds the 1 MiB evidence budget: ${animationStats.size} bytes.`);
}

console.log(
  `Validated ${filenames.length} transparent captures and a ${frameCount}-frame, `
  + `${Math.round(durationMilliseconds)}ms single-play APNG.`,
);
