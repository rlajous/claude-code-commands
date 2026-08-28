import { readFile, readdir } from 'node:fs/promises';
import { extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const siteRoot = resolve(fileURLToPath(new URL('..', import.meta.url)));
const sourceRoot = join(siteRoot, 'src');
const tokenPath = join(sourceRoot, 'styles', 'tokens.css');
const customPath = join(sourceRoot, 'styles', 'custom.css');

/** Recursively collect token-consuming source files in deterministic path order. */
async function collectFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? collectFiles(path) : [path];
  }));
  return files.flat();
}

const tokens = await readFile(tokenPath, 'utf8');
const custom = await readFile(customPath, 'utf8');
const requiredTokens = [
  '--ceibo-coral-500',
  '--ceibo-sage-300',
  '--background',
  '--foreground',
  '--text-display',
  '--space-2xl',
  '--duration-feedback',
  '--ease-out-expo',
  '--shadow-md',
];

for (const token of requiredTokens) {
  if (!tokens.includes(`${token}:`)) throw new Error(`Missing required design token: ${token}`);
}

if (!custom.includes("@import './tokens.css';")) {
  throw new Error('custom.css must import the canonical token layer.');
}

const sourceFiles = (await collectFiles(sourceRoot)).filter((path) => ['.astro', '.css'].includes(extname(path)) && path !== tokenPath);
const violations = [];
for (const path of sourceFiles) {
  const contents = await readFile(path, 'utf8');
  const lines = contents.split('\n');
  lines.forEach((line, index) => {
    if (/#[\da-f]{3,8}\b|rgba?\(|oklch\(/i.test(line)) {
      violations.push(`${relative(siteRoot, path)}:${index + 1} uses a raw color outside tokens.css`);
    }
    if (/\b\d+(?:\.\d+)?ms\b/.test(line) && !line.includes('0.01ms')) {
      violations.push(`${relative(siteRoot, path)}:${index + 1} uses a raw CSS duration outside tokens.css`);
    }
  });
}

if (violations.length > 0) {
  throw new Error(`Design-system drift detected:\n${violations.map((violation) => `- ${violation}`).join('\n')}`);
}

console.log(`Validated ${requiredTokens.length} core tokens and ${sourceFiles.length} token consumers.`);
