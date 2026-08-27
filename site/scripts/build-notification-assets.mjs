#!/usr/bin/env node

import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { basename, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import sharp from 'sharp';

const filenames = [
  'agent-finished-macos.png',
  'pr-changes-requested-macos.png',
  'pr-approved-macos.png',
];

let inputDirectory = '';
let outputDirectory = '';
for (let index = 2; index < process.argv.length; index += 1) {
  const argument = process.argv[index];
  if (argument === '--input') inputDirectory = process.argv[++index] ?? '';
  else if (argument === '--output') outputDirectory = process.argv[++index] ?? '';
  else throw new Error(`Unknown argument: ${argument}`);
}
if (!inputDirectory || !outputDirectory) {
  throw new Error('Usage: build-notification-assets.mjs --input RAW_DIR --output OUTPUT_DIR');
}

inputDirectory = resolve(inputDirectory);
outputDirectory = resolve(outputDirectory);
await mkdir(outputDirectory, { recursive: true });

const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
const smoothstep = (minimum, maximum, value) => {
  const progress = clamp((value - minimum) / (maximum - minimum), 0, 1);
  return progress * progress * (3 - (2 * progress));
};

async function removeControlledBackground(filename) {
  const sourcePath = join(inputDirectory, filename);
  const { data, info } = await sharp(sourcePath)
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;
  if (width < 250 || height < 50 || channels !== 3) {
    throw new Error(`Implausible raw capture dimensions for ${filename}: ${width}x${height}`);
  }

  const sampleSize = Math.max(2, Math.min(8, Math.floor(Math.min(width, height) / 20)));
  const samples = [];
  const corners = [
    [0, 0],
    [width - sampleSize, 0],
    [0, height - sampleSize],
    [width - sampleSize, height - sampleSize],
  ];
  for (const [startX, startY] of corners) {
    for (let y = startY; y < startY + sampleSize; y += 1) {
      for (let x = startX; x < startX + sampleSize; x += 1) {
        const offset = (y * width + x) * channels;
        samples.push([data[offset], data[offset + 1], data[offset + 2]]);
      }
    }
  }

  const background = [0, 1, 2].map((channel) => (
    Math.round(samples.reduce((total, sample) => total + sample[channel], 0) / samples.length)
  ));
  const cornerSpread = Math.max(...samples.map((sample) => Math.hypot(
    sample[0] - background[0],
    sample[1] - background[1],
    sample[2] - background[2],
  )));
  if (cornerSpread > 14) {
    throw new Error(
      `${filename} does not have a uniform controlled background (corner spread ${cornerSpread.toFixed(1)}).`,
    );
  }

  const output = Buffer.alloc(width * height * 4);
  let transparentPixels = 0;
  let opaquePixels = 0;
  for (let offset = 0, outputOffset = 0; offset < data.length; offset += 3, outputOffset += 4) {
    const red = data[offset];
    const green = data[offset + 1];
    const blue = data[offset + 2];
    const distance = Math.hypot(red - background[0], green - background[1], blue - background[2]);
    const alpha = Math.round(smoothstep(4, 24, distance) * 255);

    if (alpha <= 3) transparentPixels += 1;
    if (alpha >= 252) opaquePixels += 1;

    if (alpha > 3 && alpha < 252) {
      const normalizedAlpha = alpha / 255;
      output[outputOffset] = clamp(Math.round((red - background[0] * (1 - normalizedAlpha)) / normalizedAlpha), 0, 255);
      output[outputOffset + 1] = clamp(Math.round((green - background[1] * (1 - normalizedAlpha)) / normalizedAlpha), 0, 255);
      output[outputOffset + 2] = clamp(Math.round((blue - background[2] * (1 - normalizedAlpha)) / normalizedAlpha), 0, 255);
    } else {
      output[outputOffset] = red;
      output[outputOffset + 1] = green;
      output[outputOffset + 2] = blue;
    }
    output[outputOffset + 3] = alpha;
  }

  const pixelCount = width * height;
  if (transparentPixels / pixelCount < 0.02 || opaquePixels / pixelCount < 0.2) {
    throw new Error(
      `${filename} has implausible transparency coverage: ${transparentPixels} transparent, ${opaquePixels} opaque.`,
    );
  }

  const destination = join(outputDirectory, filename);
  await sharp(output, { raw: { width, height, channels: 4 } }).png().toFile(destination);
  const cornersAreTransparent = await sharp(destination)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true })
    .then(({ data: pixels, info: metadata }) => [
      pixels[3],
      pixels[((metadata.width - 1) * 4) + 3],
      pixels[(((metadata.height - 1) * metadata.width) * 4) + 3],
      pixels[((((metadata.height - 1) * metadata.width) + metadata.width - 1) * 4) + 3],
    ].every((alpha) => alpha <= 3));
  if (!cornersAreTransparent) throw new Error(`${filename} still has opaque corner pixels.`);

  return { filename, width, height, background, cornerSpread, transparentPixels, opaquePixels };
}

const results = [];
for (const filename of filenames) results.push(await removeControlledBackground(filename));

const frameDirectory = join(outputDirectory, '.animation-frames');
await rm(frameDirectory, { recursive: true, force: true });
await mkdir(frameDirectory, { recursive: true });
const frameList = [];
let frameNumber = 0;
const canvasWidth = Math.max(...results.map(({ width }) => width)) + 48;
const canvasHeight = Math.max(...results.map(({ height }) => height)) + 40;

async function addFrame(filename, x, opacity, duration) {
  const source = await sharp(join(outputDirectory, filename)).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const pixels = Buffer.from(source.data);
  for (let offset = 3; offset < pixels.length; offset += 4) {
    pixels[offset] = Math.round(pixels[offset] * opacity);
  }
  const foreground = await sharp(pixels, { raw: source.info }).png().toBuffer();
  const framePath = join(frameDirectory, `frame-${String(frameNumber).padStart(3, '0')}.png`);
  await sharp({
    create: { width: canvasWidth, height: canvasHeight, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  }).composite([{ input: foreground, left: Math.round(x), top: 20 }]).png().toFile(framePath);
  frameList.push({ framePath, duration });
  frameNumber += 1;
}

for (let assetIndex = 0; assetIndex < filenames.length; assetIndex += 1) {
  const filename = filenames[assetIndex];
  for (let step = 0; step < 5; step += 1) {
    const progress = (step + 1) / 5;
    const eased = 1 - ((1 - progress) ** 4);
    await addFrame(filename, 24 + ((1 - eased) * 24), eased, 0.05);
  }
  await addFrame(filename, 24, 1, assetIndex === filenames.length - 1 ? 0.5 : 0.9);
  if (assetIndex < filenames.length - 1) {
    for (let step = 0; step < 4; step += 1) {
      const progress = (step + 1) / 4;
      await addFrame(filename, 24, 1 - progress, 0.05);
    }
  }
}

const concatPath = join(frameDirectory, 'frames.txt');
const concatLines = [];
for (const { framePath, duration } of frameList) {
  concatLines.push(`file '${framePath.replaceAll("'", "'\\''")}'`);
  concatLines.push(`duration ${duration}`);
}
concatLines.push(`file '${frameList.at(-1).framePath.replaceAll("'", "'\\''")}'`);
await writeFile(concatPath, `${concatLines.join('\n')}\n`);

const animationPath = join(outputDirectory, 'notifications-macos.apng');
const ffmpeg = spawnSync('ffmpeg', [
  '-hide_banner', '-loglevel', 'error', '-y',
  '-f', 'concat', '-safe', '0', '-i', concatPath,
  '-fps_mode', 'vfr', '-plays', '1', '-f', 'apng', animationPath,
], { encoding: 'utf8' });
if (ffmpeg.status !== 0) {
  throw new Error(`Unable to create APNG: ${ffmpeg.stderr || ffmpeg.stdout}`);
}

const animationBuffer = await readFile(animationPath);
const animationMetadata = await sharp(animationBuffer).metadata();
let cursor = 8;
let animationControl = null;
let frameControlCount = 0;
let animationDurationMilliseconds = 0;
while (cursor + 12 <= animationBuffer.length) {
  const length = animationBuffer.readUInt32BE(cursor);
  const type = animationBuffer.subarray(cursor + 4, cursor + 8).toString('ascii');
  if (type === 'acTL' && length === 8) {
    animationControl = {
      frames: animationBuffer.readUInt32BE(cursor + 8),
      plays: animationBuffer.readUInt32BE(cursor + 12),
    };
  }
  if (type === 'fcTL') {
    frameControlCount += 1;
    const numerator = animationBuffer.readUInt16BE(cursor + 28);
    const denominator = animationBuffer.readUInt16BE(cursor + 30) || 100;
    animationDurationMilliseconds += (numerator / denominator) * 1000;
  }
  cursor += length + 12;
  if (type === 'IEND') break;
}
if (!animationControl || animationControl.frames < 3 || animationControl.plays !== 1) {
  throw new Error(`Invalid APNG animation control: ${JSON.stringify(animationControl)}`);
}
if (frameControlCount !== animationControl.frames) {
  throw new Error(`APNG frame mismatch: acTL=${animationControl.frames}, fcTL=${frameControlCount}`);
}

await writeFile(join(outputDirectory, 'manifest.json'), `${JSON.stringify({
  generatedAt: new Date().toISOString(),
  source: 'Production macOS notifier captured against a controlled local surface',
  sequence: filenames,
  animation: {
    filename: basename(animationPath),
    width: animationMetadata.width,
    height: animationMetadata.height,
    pages: animationControl.frames,
    loop: animationControl.plays,
    durationMilliseconds: Math.round(animationDurationMilliseconds),
  },
  images: results,
}, null, 2)}\n`);

await rm(frameDirectory, { recursive: true, force: true });
console.log(`Built ${filenames.length} transparent PNGs and ${basename(animationPath)}.`);
