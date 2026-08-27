import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { createServer } from 'node:net';
import { fileURLToPath } from 'node:url';

const siteRoot = fileURLToPath(new URL('../', import.meta.url));
const astroCli = fileURLToPath(new URL('../node_modules/astro/bin/astro.mjs', import.meta.url));

async function availablePort() {
  const server = createServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Unable to reserve a local test port.');
  const { port } = address;
  server.close();
  await once(server, 'close');
  return port;
}

const port = await availablePort();
const server = spawn(process.execPath, [astroCli, 'dev', '--ignore-lock', '--host', '127.0.0.1', '--port', String(port)], {
  cwd: siteRoot,
  env: {
    ...process.env,
    ASTRO_DEV_BACKGROUND: '0',
    ASTRO_TELEMETRY_DISABLED: '1',
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});

let output = '';
server.stdout.on('data', (chunk) => { output += chunk; });
server.stderr.on('data', (chunk) => { output += chunk; });

try {
  const route = `http://127.0.0.1:${port}/git-workflow/examples/pr-23/`;
  let response;
  for (let attempt = 0; attempt < 80; attempt += 1) {
    try {
      response = await fetch(route);
      if (response.ok) break;
    } catch {
      // The dev server is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }

  if (!response?.ok) {
    throw new Error(`Astro dev route returned ${response?.status ?? 'no response'}: ${route}\n${output}`);
  }
  const html = await response.text();
  if (!html.includes('Git Workflow') || !html.includes('rel="canonical"')) {
    throw new Error(`Astro dev route did not return the self-contained decision brief: ${route}`);
  }
  console.log(`Validated Astro dev route: ${route}`);
} finally {
  server.kill('SIGTERM');
  await Promise.race([
    once(server, 'exit'),
    new Promise((resolve) => setTimeout(resolve, 2_000)),
  ]);
  if (server.exitCode === null) server.kill('SIGKILL');
}
