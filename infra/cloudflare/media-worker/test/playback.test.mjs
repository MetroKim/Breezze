import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { webcrypto } from 'node:crypto';
import ts from 'typescript';

// Execute the real Worker implementation with an in-memory R2 test double.
// Do not stub signature verification or replace it with a test-only shortcut.
const source = await readFile(new URL('../src/index.ts', import.meta.url), 'utf8');
const js = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText;
const { default: worker } = await import(
  'data:text/javascript;base64,' + Buffer.from(js).toString('base64')
);

const key = 'breezze-qa-only-hmac-key-not-a-production-secret';
const mediaId = '417a56a2-e35a-4827-84d8-802c071fe334';
const variant = 'AAC_256';
const bytes = new Uint8Array([82, 73, 70, 70, 87, 65, 86, 69, 7, 13, 19, 29, 31, 41]);

function fakeR2(withObject = true) {
  const data = withObject ? bytes : null;
  const metadata = () => data === null ? null : {
    size: data.length,
    httpEtag: '"synthetic-qa-fixture"',
    httpMetadata: { contentType: 'audio/wav' },
  };
  return {
    async head(path) {
      return path === `audio/${mediaId}/${variant}` ? metadata() : null;
    },
    async get(path, options = {}) {
      if (path !== `audio/${mediaId}/${variant}` || data === null) return null;
      const range = options.range;
      const selected = range
        ? data.slice(range.offset, range.offset + range.length)
        : data;
      return { ...metadata(), body: new Blob([selected]).stream() };
    },
  };
}

async function urlFor({ track = mediaId, quality = variant, expiry = Date.now() + 60_000,
                         secret = key } = {}) {
  const payload = `${track}:${quality}:${expiry}`;
  const imported = await webcrypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' },
    false, ['sign'],
  );
  const signature = Buffer.from(
    await webcrypto.subtle.sign('HMAC', imported, new TextEncoder().encode(payload)),
  ).toString('base64url');
  return `https://media.breezze.test/audio/${track}/${quality}?e=${expiry}&s=${signature}`;
}

const env = () => ({ MEDIA_BUCKET: fakeR2(), MEDIA_SIGNING_KEY: key });

test('signed GET serves exact bytes without exposing them through shared caches', async () => {
  const response = await worker.fetch(new Request(await urlFor()), env());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Cache-Control'), 'private, no-store');
  assert.equal(response.headers.get('Content-Type'), 'audio/wav');
  assert.equal(response.headers.get('Accept-Ranges'), 'bytes');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);
});

test('HEAD returns the media headers but never a body', async () => {
  const response = await worker.fetch(new Request(await urlFor(), { method: 'HEAD' }), env());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Content-Length'), String(bytes.length));
  assert.equal(await response.text(), '');
});

test('byte-range seek and suffix requests return precise RFC 9110 ranges', async () => {
  const path = await urlFor();
  const response = await worker.fetch(
    new Request(path, { headers: { Range: 'bytes=4-8' } }), env());
  assert.equal(response.status, 206);
  assert.equal(response.headers.get('Content-Range'), `bytes 4-8/${bytes.length}`);
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes.slice(4, 9));

  const suffix = await worker.fetch(
    new Request(path, { headers: { Range: 'bytes=-4' } }), env());
  assert.equal(suffix.status, 206);
  assert.equal(suffix.headers.get('Content-Range'),
    `bytes ${bytes.length - 4}-${bytes.length - 1}/${bytes.length}`);
  assert.deepEqual(new Uint8Array(await suffix.arrayBuffer()), bytes.slice(-4));

  const invalid = await worker.fetch(
    new Request(path, { headers: { Range: 'bytes=999-1200' } }), env());
  assert.equal(invalid.status, 416);
  assert.equal(invalid.headers.get('Content-Range'), `bytes */${bytes.length}`);
});

test('rejects a forged track, signature or expired capability', async () => {
  const valid = await urlFor();
  for (const requestUrl of [
    valid.replace(mediaId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    valid.replace('AAC_256', 'LOSSLESS'),
    valid.replace(/s=[^&]+/, 's=forged'),
    await urlFor({ expiry: Date.now() - 1000 }),
  ]) {
    const response = await worker.fetch(new Request(requestUrl), env());
    assert.equal(response.status, 403);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
  }
});

test('fails closed for missing storage, object or disallowed operations', async () => {
  const url = await urlFor();
  assert.equal((await worker.fetch(new Request(url), {
    MEDIA_SIGNING_KEY: key,
  })).status, 503);
  assert.equal((await worker.fetch(new Request(url), {
    MEDIA_BUCKET: fakeR2(false), MEDIA_SIGNING_KEY: key,
  })).status, 404);
  assert.equal((await worker.fetch(
    new Request(url, { method: 'POST' }), env())).status, 405);
  assert.equal((await worker.fetch(
    new Request('https://media.breezze.test/audio/../private?e=1&s=x'), env())).status, 404);
});
