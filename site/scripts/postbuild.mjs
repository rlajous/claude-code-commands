import { access, readFile, readdir } from 'node:fs/promises';
import { dirname, extname, join, normalize, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { contentMap } from '../content-map.mjs';

const siteRoot = fileURLToPath(new URL('../', import.meta.url));
const distRoot = join(siteRoot, 'dist');

const requiredFiles = [
  'index.html',
  'index.md',
  'llms.txt',
  'robots.txt',
  'sitemap-index.xml',
  'git-workflow/llms.txt',
  'git-workflow/examples/pr-23/index.html',
  ...contentMap.flatMap(({ slug }) => [`${slug}/index.html`, `${slug}/index.md`]),
];

for (const file of requiredFiles) {
  await access(join(distRoot, file)).catch(() => {
    throw new Error(`Required build output is missing: ${file}`);
  });
}

const rootLlms = await readFile(join(distRoot, 'llms.txt'), 'utf8');
const productLlms = await readFile(join(distRoot, 'git-workflow/llms.txt'), 'utf8');
if (!rootLlms.startsWith('# Agent Tooling\n\n> ') || !rootLlms.includes('## Products')) {
  throw new Error('Root llms.txt does not follow the expected concise index structure.');
}
if (!productLlms.startsWith('# Git Workflow\n\n> ') || !productLlms.includes('## Documentation')) {
  throw new Error('Product llms.txt does not follow the expected concise index structure.');
}

const htmlFiles = [];
/** Recursively collect built HTML documents for metadata and link validation. */
async function collectHtml(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) await collectHtml(path);
    else if (entry.name.endsWith('.html')) htmlFiles.push(path);
  }
}
await collectHtml(distRoot);

/** Resolve one local HTML reference to its expected static-build filesystem target. */
function localTarget(rawValue, htmlPath) {
  const value = rawValue.replaceAll('&amp;', '&').split('#')[0].split('?')[0];
  if (!value || /^(?:https?:|mailto:|tel:|data:|javascript:)/.test(value)) return undefined;
  if (value.startsWith('/')) return resolve(distRoot, value.slice(1));
  return resolve(dirname(htmlPath), value);
}

for (const htmlPath of htmlFiles) {
  const html = await readFile(htmlPath, 'utf8');
  const outputPath = normalize(relative(distRoot, htmlPath)).split(sep).join('/');
  const route = outputPath === 'index.html'
    ? '/'
    : outputPath === '404.html'
      ? '/404'
      : `/${outputPath.replace(/index\.html$/, '')}`;
  if (route !== '/404' && !html.includes('rel="canonical"')) throw new Error(`Missing canonical URL in ${route}`);
  if (!route.includes('/pagefind/') && route !== '/404') {
    if (!html.includes('rel="describedby"')) throw new Error(`Missing llms.txt relation in ${route}`);
    if (route !== '/git-workflow/examples/pr-23/' && !html.includes('type="text/markdown"')) {
      throw new Error(`Missing Markdown alternate in ${route}`);
    }
  }

  for (const match of html.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
    let target = localTarget(match[1], htmlPath);
    if (!target) continue;
    if (match[1].endsWith('/') || extname(target) === '') target = join(target, 'index.html');
    const normalizedTarget = normalize(target);
    if (!normalizedTarget.startsWith(distRoot)) throw new Error(`Build link escapes dist in ${route}: ${match[1]}`);
    await access(normalizedTarget).catch(() => {
      throw new Error(`Broken local build link in ${route}: ${match[1]}`);
    });
  }
}

const rootHtml = await readFile(join(distRoot, 'index.html'), 'utf8');
const productHtml = await readFile(join(distRoot, 'git-workflow/index.html'), 'utf8');
if (!rootHtml.includes('"@type":"WebSite"')) throw new Error('Root WebSite structured data is missing.');
if (!productHtml.includes('"@type":"SoftwareSourceCode"')) throw new Error('Product SoftwareSourceCode structured data is missing.');

console.log(`Validated ${htmlFiles.length} HTML pages, ${requiredFiles.length} required files, local links, metadata, and LLM indexes.`);
