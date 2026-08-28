#!/usr/bin/env node

import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createServer } from 'node:net';
import { test } from 'node:test';
import { fetchWithTimeout } from './lib/http.mjs';

test('aborts a route request when a server accepts but never responds', async () => {
  const sockets = new Set();
  const server = createServer((socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Unable to reserve a timeout test port.');

  const startedAt = Date.now();
  try {
    await assert.rejects(
      fetchWithTimeout(`http://127.0.0.1:${address.port}/stalled`, 75),
      (error) => error instanceof Error && ['AbortError', 'TimeoutError'].includes(error.name),
    );
    assert.ok(Date.now() - startedAt < 1_000, 'The request exceeded its bounded deadline.');
  } finally {
    for (const socket of sockets) socket.destroy();
    server.close();
    await once(server, 'close');
  }
});
