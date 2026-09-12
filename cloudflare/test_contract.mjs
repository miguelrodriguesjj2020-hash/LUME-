import test from 'node:test';
import assert from 'node:assert/strict';
import { webcrypto } from 'node:crypto';
if (!globalThis.crypto) globalThis.crypto = webcrypto;
if (!globalThis.btoa) globalThis.btoa = s => Buffer.from(s, 'binary').toString('base64');
if (!globalThis.atob) globalThis.atob = s => Buffer.from(s, 'base64').toString('binary');

import { passwordMac, signMedia, signSession, verifyMedia, verifySession } from './src/crypto.js';
import { shouldAcceptProgress, validateCatalogManifest, validateProgress } from './src/catalog.js';
import { runtimeReady } from './src/worker.js';

const SECRET = 'x'.repeat(48);

test('session HMAC round-trip and expiry', async () => {
  const now = 1700000000000;
  const token = await signSession({ sub: 'p1', role: 'consumer', exp: now + 5000 }, SECRET);
  assert.equal((await verifySession(token, SECRET, now)).sub, 'p1');
  assert.equal(await verifySession(token, SECRET, now + 6000), null);
  assert.equal(await verifySession(token + 'x', SECRET, now), null);
});

test('password MAC is deterministic and peppered', async () => {
  assert.equal(await passwordMac(SECRET, 'pw'), await passwordMac(SECRET, 'pw'));
  assert.notEqual(await passwordMac(SECRET, 'pw'), await passwordMac('y'.repeat(48), 'pw'));
});

test('media signatures expire and reject tampering', async () => {
  const now = 1700000000000, exp = now + 60000;
  const sig = await signMedia('ed1', exp, SECRET);
  assert.equal(await verifyMedia('ed1', exp, sig, SECRET, now), true);
  assert.equal(await verifyMedia('ed2', exp, sig, SECRET, now), false);
  assert.equal(await verifyMedia('ed1', exp, sig, SECRET, exp + 1), false);
});

test('catalog validator preserves mobile contract', () => {
  const manifest = { revision: 2, works: [{ id: 'w1', type: 'hq', displayTitle: 'HQ', editions: [{ id: 'e1', format: 'cbz', sourceFileId: 'drive1', fileName: 'hq.cbz' }], editorialSections: ['Recomendações'] }], tombstones: [] };
  assert.equal(validateCatalogManifest(manifest), true);
  assert.throws(() => validateCatalogManifest({ ...manifest, works: [...manifest.works, manifest.works[0]] }), /duplicate work id/);
});

test('progress anti-regression semantics match reference backend', () => {
  const old = { completed: false, clientUpdatedAt: 20 };
  assert.equal(shouldAcceptProgress(old, { completed: false, clientUpdatedAt: 19 }), false);
  assert.equal(shouldAcceptProgress(old, { completed: false, clientUpdatedAt: 20 }), true);
  assert.equal(shouldAcceptProgress(old, { completed: true, clientUpdatedAt: 1 }), true);
  assert.equal(shouldAcceptProgress({ completed: true, clientUpdatedAt: 20 }, { completed: false, clientUpdatedAt: 30 }), false);
  assert.doesNotThrow(() => validateProgress('e1', { opId: 'o1', clientUpdatedAt: 1, completed: false, percent: .2, locator: { page: 2 } }));
});

test('production readiness fails closed', () => {
  assert.equal(runtimeReady({}).ok, false);
  assert.equal(runtimeReady({ DB: {}, AUTH_SECRET: SECRET, MEDIA_SECRET: SECRET, PASSWORD_PEPPER: SECRET, GDRIVE_CLIENT_EMAIL: 'x@y', GDRIVE_PRIVATE_KEY: 'pem' }).ok, true);
});
