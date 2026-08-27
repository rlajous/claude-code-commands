import { copyFile, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join, normalize, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { contentMap, specialRoutes } from '../content-map.mjs';

const siteRoot = fileURLToPath(new URL('../', import.meta.url));
const repoRoot = resolve(siteRoot, '..');
const generatedDocs = join(siteRoot, 'src/content/docs/generated');
const publicRoot = join(siteRoot, 'public');
const generatedAssets = join(publicRoot, 'assets');
const productPublic = join(publicRoot, 'git-workflow');
const repositoryUrl = 'https://github.com/rlajous/claude-code-commands';
const productionOrigin = 'https://agents.navarrolajous.com';

const normalizeRelative = (value) => normalize(value).split(sep).join('/').replace(/^\.\//, '');
const routeForSlug = (slug) => `/${slug.replace(/^\/+|\/+$/g, '')}/`;
const quote = (value) => JSON.stringify(value);

function ensureInsideRepo(path) {
  const fromRoot = relative(repoRoot, path);
  if (fromRoot.startsWith('..') || fromRoot.includes(`${sep}..${sep}`)) {
    throw new Error(`Refusing to access a path outside the repository: ${path}`);
  }
}

function stripFrontmatter(markdown) {
  return markdown.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, '');
}

function stripFirstHeading(markdown) {
  return markdown.replace(/^#\s+[^\n]+\r?\n+/, '');
}

const sourceToEntry = new Map();
const slugSet = new Set();

for (const entry of contentMap) {
  const source = normalizeRelative(entry.source);
  if (sourceToEntry.has(source)) throw new Error(`Duplicate content source: ${source}`);
  if (slugSet.has(entry.slug)) throw new Error(`Duplicate content slug: ${entry.slug}`);
  if (!entry.title || !entry.description || !entry.section || !Number.isFinite(entry.order)) {
    throw new Error(`Incomplete content map entry for ${source}`);
  }
  sourceToEntry.set(source, entry);
  slugSet.add(entry.slug);
}

await rm(generatedDocs, { recursive: true, force: true });
await rm(generatedAssets, { recursive: true, force: true });
await rm(productPublic, { recursive: true, force: true });
await mkdir(generatedDocs, { recursive: true });
await mkdir(generatedAssets, { recursive: true });
await mkdir(productPublic, { recursive: true });

const copiedAssets = new Map();
const assetInfo = new Map();

async function copyAsset(sourcePath, publicPath) {
  const sourceAbsolute = resolve(repoRoot, sourcePath);
  const targetAbsolute = resolve(publicRoot, publicPath.replace(/^\//, ''));
  ensureInsideRepo(sourceAbsolute);
  await mkdir(dirname(targetAbsolute), { recursive: true });
  if (!copiedAssets.has(sourcePath)) {
    await copyFile(sourceAbsolute, targetAbsolute);
    if (/\.(?:png|jpe?g)$/i.test(sourcePath)) {
      const metadata = await sharp(sourceAbsolute).metadata();
      if (!metadata.width || !metadata.height) throw new Error(`Unable to read image dimensions: ${sourcePath}`);
      const widths = [...new Set([480, 960, metadata.width].filter((width) => width <= metadata.width))].sort((a, b) => a - b);
      const variants = [];
      for (const width of widths) {
        const variantPath = publicPath.replace(/\.[^.]+$/, `-${width}.webp`);
        const variantAbsolute = resolve(publicRoot, variantPath.replace(/^\//, ''));
        await sharp(sourceAbsolute).resize({ width, withoutEnlargement: true }).webp({ quality: 82 }).toFile(variantAbsolute);
        variants.push({ width, path: variantPath });
      }
      assetInfo.set(publicPath, { width: metadata.width, height: metadata.height, variants });
    }
    copiedAssets.set(sourcePath, publicPath);
  }
  return publicPath;
}

async function resolveLocalLink(rawTarget, source) {
  const cleaned = rawTarget.trim().replace(/^<|>$/g, '');
  if (/^(?:https?:|mailto:|tel:)/.test(cleaned) || cleaned.startsWith('#')) return cleaned;

  const hashIndex = cleaned.indexOf('#');
  const targetWithoutHash = hashIndex === -1 ? cleaned : cleaned.slice(0, hashIndex);
  const hash = hashIndex === -1 ? '' : cleaned.slice(hashIndex);
  const targetAbsolute = resolve(dirname(resolve(repoRoot, source)), targetWithoutHash);
  ensureInsideRepo(targetAbsolute);
  const resolvedSource = normalizeRelative(relative(repoRoot, targetAbsolute));

  const mappedEntry = sourceToEntry.get(resolvedSource);
  if (mappedEntry) return `${routeForSlug(mappedEntry.slug)}${hash}`;

  if (specialRoutes.has(resolvedSource)) return `${specialRoutes.get(resolvedSource)}${hash}`;

  if (resolvedSource.startsWith('docs/assets/')) {
    const destination = `/assets/${resolvedSource.slice('docs/assets/'.length)}`;
    await copyAsset(resolvedSource, destination);
    return `${destination}${hash}`;
  }

  const configExample = resolvedSource.match(/^examples\/([^/]+)\/config\.yaml$/);
  if (configExample) {
    const destination = `/git-workflow/examples/config/${configExample[1]}.yaml`;
    await copyAsset(resolvedSource, destination);
    return `${destination}${hash}`;
  }

  throw new Error(`Unmapped internal link in ${source}: ${rawTarget} resolves to ${resolvedSource}`);
}

async function rewriteMarkdown(markdown, source) {
  const matches = [...markdown.matchAll(/\]\(([^)]+)\)/g)];
  let output = '';
  let cursor = 0;
  for (const match of matches) {
    output += markdown.slice(cursor, match.index);
    const target = await resolveLocalLink(match[1], source);
    output += `](${target})`;
    cursor = match.index + match[0].length;
  }
  return responsiveMarkdownImages(output + markdown.slice(cursor));
}

const escapeHtml = (value) => value
  .replaceAll('&', '&amp;')
  .replaceAll('"', '&quot;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;');

function responsiveImage(alt, source) {
  const info = assetInfo.get(source);
  if (!info) throw new Error(`Responsive image metadata was not generated for ${source}`);
  const fallback = info.variants.at(-1)?.path ?? source;
  const srcset = info.variants.map(({ width, path }) => `${path} ${width}w`).join(', ');
  return `<img src="${fallback}" srcset="${srcset}" sizes="(max-width: 52rem) calc(100vw - 2rem), 48rem" width="${info.width}" height="${info.height}" loading="lazy" decoding="async" alt="${escapeHtml(alt)}">`;
}

function responsiveMarkdownImages(markdown) {
  const nestedImages = markdown.replace(
    /\[!\[([^\]]*)\]\((\/assets\/[^)]+)\)\]\(([^)]+)\)/g,
    (_, alt, source, href) => `<a href="${escapeHtml(href)}">${responsiveImage(alt, source)}</a>`,
  );
  return nestedImages.replace(
    /!\[([^\]]*)\]\((\/assets\/[^)]+)\)/g,
    (_, alt, source) => responsiveImage(alt, source),
  );
}

function frontmatter(entry) {
  const values = [
    '---',
    `title: ${quote(entry.title)}`,
    `description: ${quote(entry.description)}`,
    `editUrl: ${quote(`${repositoryUrl}/edit/main/${entry.source}`)}`,
    `lastUpdated: true`,
    'sidebar:',
    `  order: ${entry.order}`,
  ];
  if (entry.template === 'splash') {
    values.push(
      'template: splash',
      'hero:',
      '  title: Git Workflow',
      '  tagline: Twenty cross-agent skills for shipping software with evidence and control.',
      '  actions:',
      '    - text: Install Git Workflow',
      '      link: /git-workflow/installation/',
      '      icon: right-arrow',
      '    - text: View on GitHub',
      `      link: ${repositoryUrl}`,
      '      variant: minimal',
    );
  }
  values.push('---', '');
  return values.join('\n');
}

const generatedEntries = [];
for (const entry of contentMap) {
  const sourceAbsolute = resolve(repoRoot, entry.source);
  ensureInsideRepo(sourceAbsolute);
  let markdown;
  try {
    markdown = await readFile(sourceAbsolute, 'utf8');
  } catch (error) {
    throw new Error(`Missing canonical content source: ${entry.source}`, { cause: error });
  }

  const body = await rewriteMarkdown(stripFirstHeading(stripFrontmatter(markdown)).trim(), entry.source);
  const rendered = `${frontmatter(entry)}${body}\n`;
  const generatedPath = join(generatedDocs, `${entry.slug}.md`);
  await mkdir(dirname(generatedPath), { recursive: true });
  await writeFile(generatedPath, rendered);

  const mirrorPath = join(publicRoot, entry.slug, 'index.md');
  await mkdir(dirname(mirrorPath), { recursive: true });
  await writeFile(mirrorPath, `# ${entry.title}\n\n> ${entry.description}\n\n${body}\n`);
  generatedEntries.push({ ...entry, route: routeForSlug(entry.slug) });
}

const manifest = JSON.parse(await readFile(resolve(repoRoot, '.codex-plugin/plugin.json'), 'utf8'));
const skillCount = (await readdir(resolve(repoRoot, 'skills'), { withFileTypes: true }))
  .filter((entry) => entry.isDirectory()).length;
const agentCount = (await readdir(resolve(repoRoot, 'agents'), { withFileTypes: true }))
  .filter((entry) => entry.isFile() && entry.name.endsWith('.md')).length;

const rootIndex = `# Agent Tooling

> Open-source workflows that help coding agents ship software with evidence and control.

Git Workflow is the first project in Agent Tooling. It provides ${skillCount} shared Claude Code and Codex skills for Git, pull requests, releases, QA, review automation, decision briefs, and private local notifications.

## Products

- [Git Workflow](${productionOrigin}/git-workflow/index.md): Installation, operational workflows, and reference documentation for version ${manifest.version}.

## Source

- [GitHub repository](${repositoryUrl}): Source code, issues, releases, and canonical Markdown documentation.
`;
await writeFile(join(publicRoot, 'index.md'), rootIndex);

const rootLlms = `# Agent Tooling

> Open-source tools that help coding agents ship software with evidence and control.

This site is maintained by Rodrigo Navarro Lajous. Public documentation is in English and links to clean Markdown representations for agent use.

## Products

- [Git Workflow](${productionOrigin}/git-workflow/llms.txt): Cross-agent Git, pull request, release, QA, review, brief, and notification workflows for Claude Code and Codex.

## Source

- [Agent Tooling overview](${productionOrigin}/index.md): Human and agent-readable introduction.
- [GitHub repository](${repositoryUrl}): Canonical source, releases, and issue tracker.
`;
await writeFile(join(publicRoot, 'llms.txt'), rootLlms);

const productLinks = generatedEntries
  .map((entry) => `- [${entry.title}](${productionOrigin}${entry.route}index.md): ${entry.description}`)
  .join('\n');
const productLlms = `# Git Workflow

> Version ${manifest.version} provides ${skillCount} host-neutral workflow skills and ${agentCount} specialized agents for Claude Code and Codex.

Claude Code invokes installed marketplace skills as \`/git-workflow:skill-name\`. Codex invokes skills as \`$skill-name\`. Use either an installed plugin or checkout-local discovery in one session, never both.

## Documentation

${productLinks}

## Examples

- [PR #23 decision brief](${productionOrigin}/git-workflow/examples/pr-23/): A self-contained, human-readable HTML explanation with workflow and notification evidence.

## Optional

- [Source repository](${repositoryUrl}): Runtime code, tests, release history, and contribution contracts.
- [Latest release](${repositoryUrl}/releases/latest): Current published package and release notes.
`;
await writeFile(join(productPublic, 'llms.txt'), productLlms);

for (const platform of ['nestjs', 'nextjs', 'python', 'react-native', 'monorepo']) {
  await copyAsset(`examples/${platform}/config.yaml`, `/git-workflow/examples/config/${platform}.yaml`);
}

const briefSource = await readFile(resolve(repoRoot, 'docs/examples/change-brief-pr-23.html'), 'utf8');
const briefHead = `\n<link rel="canonical" href="${productionOrigin}/git-workflow/examples/pr-23/">\n<link rel="describedby" href="${productionOrigin}/git-workflow/llms.txt">\n`;
const briefOutput = briefSource.includes('</head>') ? briefSource.replace('</head>', `${briefHead}</head>`) : briefSource;
const briefTarget = join(productPublic, 'examples/pr-23/index.html');
await mkdir(dirname(briefTarget), { recursive: true });
await writeFile(briefTarget, briefOutput);

console.log(`Synced ${generatedEntries.length} canonical documents for Git Workflow ${manifest.version}.`);
