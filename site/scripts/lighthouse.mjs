import { createServer } from 'node:http';
import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import { extname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { launch } from 'chrome-launcher';
import lighthouse from 'lighthouse';
import { chromium } from 'playwright';

const siteRoot = fileURLToPath(new URL('../', import.meta.url));
const distRoot = join(siteRoot, 'dist');
const reportRoot = join(siteRoot, '.lighthouseci');
const routes = ['/', '/git-workflow/', '/git-workflow/review-watch/'];
const categoryNames = ['performance', 'accessibility', 'best-practices', 'seo'];
const minimumScore = 0.95;

await access(join(distRoot, 'index.html')).catch(() => {
  throw new Error('Build output is missing. Run npm run build before Lighthouse.');
});
await mkdir(reportRoot, { recursive: true });

const contentTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.md', 'text/markdown; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.txt', 'text/plain; charset=utf-8'],
  ['.wasm', 'application/wasm'],
  ['.webp', 'image/webp'],
  ['.xml', 'application/xml; charset=utf-8'],
]);

const server = createServer(async (request, response) => {
  try {
    const url = new URL(request.url ?? '/', 'http://localhost');
    const decodedPath = decodeURIComponent(url.pathname);
    let target = resolve(distRoot, `.${decodedPath}`);
    if (relative(distRoot, target).startsWith('..')) throw new Error('Path traversal rejected.');
    if (decodedPath.endsWith('/')) target = join(target, 'index.html');
    const body = await readFile(target);
    response.writeHead(200, { 'content-type': contentTypes.get(extname(target)) ?? 'application/octet-stream' });
    response.end(body);
  } catch {
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    response.end('Not found');
  }
});

await new Promise((resolveListen) => server.listen(0, '127.0.0.1', resolveListen));
const address = server.address();
if (!address || typeof address === 'string') throw new Error('Unable to determine local audit port.');

const chrome = await launch({
  chromePath: chromium.executablePath(),
  chromeFlags: ['--headless=new', '--no-sandbox', '--disable-gpu'],
});

let failed = false;
try {
  for (const route of routes) {
    const url = `http://127.0.0.1:${address.port}${route}`;
    const result = await lighthouse(url, {
      port: chrome.port,
      logLevel: 'error',
      output: 'json',
      onlyCategories: categoryNames,
    });
    if (!result) throw new Error(`Lighthouse returned no result for ${route}`);
    const scores = Object.fromEntries(categoryNames.map((name) => [name, result.lhr.categories[name].score ?? 0]));
    const summary = categoryNames.map((name) => `${name} ${Math.round(scores[name] * 100)}`).join(' · ');
    console.log(`${route} ${summary}`);
    for (const [name, score] of Object.entries(scores)) {
      if (score < minimumScore) {
        failed = true;
        console.error(`${route} failed ${name}: expected at least ${minimumScore * 100}, received ${Math.round(score * 100)}`);
      }
    }
    const reportName = route === '/' ? 'root' : route.replaceAll('/', '-').replace(/^-|-$/g, '');
    await writeFile(join(reportRoot, `${reportName}.report.json`), JSON.stringify(result.lhr));
  }
} finally {
  chrome.kill();
  await new Promise((resolveClose, rejectClose) => server.close((error) => error ? rejectClose(error) : resolveClose()));
}

if (failed) process.exitCode = 1;
