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

/** Normalize repository-relative paths to stable forward-slash identifiers. */
const normalizeRelative = (value) => normalize(value).split(sep).join('/').replace(/^\.\//, '');

/** Convert one configured slug to its canonical trailing-slash public route. */
const routeForSlug = (slug) => `/${slug.replace(/^\/+|\/+$/g, '')}/`;

/** Serialize frontmatter values without introducing YAML quoting ambiguity. */
const quote = (value) => JSON.stringify(value);

/** Reject any generated-content access that escapes the repository boundary. */
function ensureInsideRepo(path) {
  const fromRoot = relative(repoRoot, path);
  if (fromRoot.startsWith('..') || fromRoot.includes(`${sep}..${sep}`)) {
    throw new Error(`Refusing to access a path outside the repository: ${path}`);
  }
}

/** Remove canonical source frontmatter before generating Starlight frontmatter. */
function stripFrontmatter(markdown) {
  return markdown.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, '');
}

/** Remove the source H1 because the generated page supplies its own title. */
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

/** Copy one referenced asset and generate bounded responsive image variants. */
async function copyAsset(sourcePath, publicPath) {
  const sourceAbsolute = resolve(repoRoot, sourcePath);
  const targetAbsolute = resolve(publicRoot, publicPath.replace(/^\//, ''));
  ensureInsideRepo(sourceAbsolute);
  await mkdir(dirname(targetAbsolute), { recursive: true });
  if (!copiedAssets.has(sourcePath)) {
    await copyFile(sourceAbsolute, targetAbsolute);
    if (/\.(?:apng|png|jpe?g)$/i.test(sourcePath)) {
      const metadata = await sharp(sourceAbsolute).metadata();
      if (!metadata.width || !metadata.height) throw new Error(`Unable to read image dimensions: ${sourcePath}`);
      const widths = /\.apng$/i.test(sourcePath)
        ? []
        : [...new Set([480, 960, metadata.width].filter((width) => width <= metadata.width))].sort((a, b) => a - b);
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

/** Map one canonical Markdown link to a validated public route or copied asset. */
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

/** Rewrite every local Markdown link while preserving external and anchor targets. */
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

/** Escape attribute text used in generated responsive image markup. */
const escapeHtml = (value) => value
  .replaceAll('&', '&amp;')
  .replaceAll('"', '&quot;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;');

/** Render one intrinsic-size responsive image, prioritizing the product page's LCP evidence. */
function responsiveImage(alt, source) {
  const info = assetInfo.get(source);
  if (!info) throw new Error(`Responsive image metadata was not generated for ${source}`);
  const fallback = info.variants.at(-1)?.path ?? source;
  const srcset = info.variants.map(({ width, path }) => `${path} ${width}w`).join(', ');
  const responsiveAttributes = srcset
    ? ` srcset="${srcset}" sizes="(max-width: 52rem) calc(100vw - 2rem), 48rem"`
    : '';
  const loadingAttributes = source === '/assets/agent-tooling-site.png'
    ? 'loading="eager" decoding="async" fetchpriority="high"'
    : 'loading="lazy" decoding="async"';
  return `<img src="${fallback}"${responsiveAttributes} width="${info.width}" height="${info.height}" ${loadingAttributes} alt="${escapeHtml(alt)}">`;
}

/** Replace local Markdown images, including linked images, with responsive HTML. */
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

/** Convert the small supported Mermaid flowchart subset into semantic, responsive process maps. */
function renderFlowcharts(markdown, source) {
  let diagramIndex = 0;
  return markdown.replace(/```mermaid\s*\n([\s\S]*?)```/g, (_, definition) => {
    diagramIndex += 1;
    const lines = definition.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
    if (!/^flowchart\s+(?:LR|RL|TD|TB)$/.test(lines.shift() ?? '')) {
      throw new Error(`Unsupported Mermaid diagram in ${source}: only flowcharts are accepted`);
    }

    const labels = new Map();
    const edges = [];
    for (const line of lines) {
      const edge = line.match(/^([A-Za-z][\w-]*)(?:\[([^\]]+)\])?\s*-->\s*(?:\|([^|]+)\|\s*)?([A-Za-z][\w-]*)(?:\[([^\]]+)\])?$/);
      if (!edge) throw new Error(`Unsupported Mermaid edge in ${source}: ${line}`);
      const [, sourceId, sourceLabel, edgeLabel, targetId, targetLabel] = edge;
      if (sourceLabel) labels.set(sourceId, sourceLabel);
      if (targetLabel) labels.set(targetId, targetLabel);
      edges.push({ sourceId, targetId, label: edgeLabel?.trim() ?? '' });
    }
    if (edges.length === 0) throw new Error(`Empty Mermaid flowchart in ${source}`);

    const groups = [];
    const groupBySource = new Map();
    for (const edge of edges) {
      let group = groupBySource.get(edge.sourceId);
      if (!group) {
        group = { sourceId: edge.sourceId, edges: [] };
        groupBySource.set(edge.sourceId, group);
        groups.push(group);
      }
      group.edges.push(edge);
    }

    const cleanLabel = (value) => escapeHtml(value.replace(/<br\s*\/?\s*>/gi, ' · ').replace(/<[^>]+>/g, ''));
    const title = source === 'docs/REVIEW_WATCH.md'
      ? 'From review request to ready for merge'
      : source === 'docs/NOTIFICATIONS.md'
        ? 'One daemon, two notification channels'
        : `Workflow ${diagramIndex}`;
    const diagramId = `workflow-${normalizeRelative(source).replace(/[^a-z0-9]+/gi, '-')}-${diagramIndex}`;
    const steps = groups.map((group, index) => {
      const targets = group.edges.map((edge) => {
        const state = /blocking|request_changes/i.test(`${edge.label} ${labels.get(edge.targetId) ?? ''}`)
          ? 'blocking'
          : /clean|approve|ready/i.test(`${edge.label} ${labels.get(edge.targetId) ?? ''}`)
            ? 'positive'
            : 'neutral';
        const edgeLabel = edge.label
          ? `<span class="workflow-edge-label">${cleanLabel(edge.label)}</span>`
          : '';
        return `<li class="workflow-target" data-state="${state}">${edgeLabel}<strong>${cleanLabel(labels.get(edge.targetId) ?? edge.targetId)}</strong></li>`;
      }).join('');
      return `<li class="workflow-step"><div class="workflow-source"><span>${String(index + 1).padStart(2, '0')}</span><strong>${cleanLabel(labels.get(group.sourceId) ?? group.sourceId)}</strong></div><span class="workflow-connector" aria-hidden="true"></span><ul class="workflow-targets">${targets}</ul></li>`;
    }).join('');

    return `<figure class="workflow-diagram" aria-labelledby="${diagramId}"><figcaption id="${diagramId}"><span>Process map</span><strong>${escapeHtml(title)}</strong><small>${groups.length} handoffs</small></figcaption><ol class="workflow-steps">${steps}</ol></figure>`;
  });
}

/** Build deterministic Starlight frontmatter for one declarative content entry. */
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

  const markdownBody = await rewriteMarkdown(stripFirstHeading(stripFrontmatter(markdown)).trim(), entry.source);
  const body = renderFlowcharts(markdownBody, entry.source);
  const rendered = `${frontmatter(entry)}${body}\n`;
  const generatedPath = join(generatedDocs, `${entry.slug}.md`);
  await mkdir(dirname(generatedPath), { recursive: true });
  await writeFile(generatedPath, rendered);

  const mirrorPath = join(publicRoot, entry.slug, 'index.md');
  await mkdir(dirname(mirrorPath), { recursive: true });
  await writeFile(mirrorPath, `# ${entry.title}\n\n> ${entry.description}\n\n${markdownBody}\n`);
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

console.log(`Synced ${generatedEntries.length} canonical documents for Git Workflow ${manifest.version}.`);
