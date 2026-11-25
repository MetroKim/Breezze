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
  const audioKey = `audio/${mediaId}/${variant}`;
  const videoKey = `video/${mediaId}/original.mp4`;
  const metadata = (path) => data === null ? null : {
    size: data.length,
    httpEtag: '"synthetic-qa-fixture"',
    httpMetadata: { contentType: path === videoKey ? 'video/mp4' : 'audio/wav' },
  };
  return {
    async head(path) {
      return path === audioKey || path === videoKey ? metadata(path) : null;
    },
    async get(path, options = {}) {
      if ((path !== audioKey && path !== videoKey) || data === null) return null;
      const range = options.range;
      const selected = range
        ? data.slice(range.offset, range.offset + range.length)
        : data;
      return { ...metadata(path), body: new Blob([selected]).stream() };
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


async function videoUrlFor({
  assetId = mediaId, mode = 'stream', expiry = Date.now() + 60_000,
} = {}) {
  const payload = `video:${assetId}:${mode}:${expiry}`;
  const imported = await webcrypto.subtle.importKey(
    'raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' },
    false, ['sign'],
  );
  const signature = Buffer.from(
    await webcrypto.subtle.sign('HMAC', imported, new TextEncoder().encode(payload)),
  ).toString('base64url');
  return `https://media.breezze.test/video/${assetId}/${mode}?e=${expiry}&s=${signature}`;
}

test('signed licensed video streams exact MP4 bytes with byte-range seeking', async () => {
  const url = await videoUrlFor({ mode: 'stream' });
  const response = await worker.fetch(new Request(url), env());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Content-Type'), 'video/mp4');
  assert.equal(response.headers.get('Cache-Control'), 'private, no-store');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);

  const seek = await worker.fetch(new Request(url, {
    headers: { Range: 'bytes=3-7' },
  }), env());
  assert.equal(seek.status, 206);
  assert.equal(seek.headers.get('Content-Range'), `bytes 3-7/${bytes.length}`);
  assert.deepEqual(new Uint8Array(await seek.arrayBuffer()), bytes.slice(3, 8));
});

test('video offline link uses a separate purpose and Content-Disposition', async () => {
  const download = await videoUrlFor({ mode: 'download' });
  const response = await worker.fetch(new Request(download), env());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Content-Disposition'),
    'attachment; filename="breezze-video.mp4"');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);

  for (const changed of [
    download.replace('/download?', '/stream?'),
    download.replace(mediaId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    download.replace(/s=[^&]+/, 's=forged'),
  ]) {
    assert.equal((await worker.fetch(new Request(changed), env())).status, 403);
  }
  assert.equal((await worker.fetch(new Request(await videoUrlFor({
    expiry: Date.now() - 1000,
  })), env())).status, 403);
});

test('video signatures cannot be repurposed for signed audio delivery', async () => {
  const signed = await videoUrlFor({ mode: 'stream' });
  const changed = signed.replace('/video/', '/audio/');
  const response = await worker.fetch(new Request(changed), env());
  assert.notEqual(response.status, 200);
  assert.equal((await worker.fetch(new Request(signed), {
    MEDIA_BUCKET: fakeR2(false), MEDIA_SIGNING_KEY: key,
  })).status, 404);
});

test('signed audio download reuses ingested AAC_256 bytes, not a missing download object', async () => {
  const downloadUrl = await urlFor({ quality: 'download' });
  const response = await worker.fetch(new Request(downloadUrl), env());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Content-Type'), 'audio/wav');
  assert.equal(response.headers.get('Content-Disposition'),
    'attachment; filename="breezze-audio.m4a"');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), bytes);

  // Signatures are purpose-specific: changing a streaming URL to the
  // download path must not give a listener unauthorized download rights.
  const streamingUrl = await urlFor({ quality: 'AAC_256' });
  const forged = streamingUrl.replace('/AAC_256?', '/download?');
  assert.equal((await worker.fetch(new Request(forged), env())).status, 403);

  const head = await worker.fetch(new Request(downloadUrl, { method: 'HEAD' }), env());
  assert.equal(head.status, 200);
  assert.equal(head.headers.get('Content-Length'), String(bytes.length));
});


async function ingestUrlFor(trackId, quality, mime, size, expiry = Date.now() + 60_000) {
  const payload = `ingest:${trackId}:${quality}:${mime}:${size}:${expiry}`;
  const imported = await webcrypto.subtle.importKey(
    'raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' },
    false, ['sign'],
  );
  const sig = Buffer.from(await webcrypto.subtle.sign(
    'HMAC', imported, new TextEncoder().encode(payload),
  )).toString('base64url');
  return `https://media.breezze.test/ingest/audio/${trackId}/${quality}?m=${encodeURIComponent(mime)}&b=${size}&e=${expiry}&s=${sig}`;
}

test('signed ingest accepts real audio magic, never changes an existing asset', async () => {
  const uploaded = new Map();
  const bucket = {
    head: async path => uploaded.has(path) ? { size: uploaded.get(path).length } : null,
    async put(path, body, options) {
      const contents = new Uint8Array(await new Response(body).arrayBuffer());
      uploaded.set(path, contents);
      return { size: contents.length, httpMetadata: options.httpMetadata };
    },
    async get(path, options) {
      const contents = uploaded.get(path);
      if (!contents) return null;
      return { body: new Blob([contents.slice(options?.range?.offset ?? 0,
        options?.range ? options.range.offset + options.range.length : contents.length)]).stream() };
    },
    async delete(path) { uploaded.delete(path); },
  };
  const environment = { MEDIA_BUCKET: bucket, MEDIA_SIGNING_KEY: key };
  const data = new Uint8Array([0,0,0,16,102,116,121,112,109,52,97,32,9,5,1,2]);
  const url = await ingestUrlFor(mediaId, 'AAC_256', 'audio/mp4', data.length);
  const request = () => new Request(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'audio/mp4', 'Content-Length': String(data.length) },
    body: data,
  });
  assert.equal((await worker.fetch(request(), environment)).status, 201);
  assert.deepEqual(uploaded.get(`audio/${mediaId}/AAC_256`), data);
  assert.equal((await worker.fetch(request(), environment)).status, 409);
  assert.equal((await worker.fetch(new Request(url.replace(/s=[^&]+/, 's=bad'), {
    method: 'PUT', headers: { 'Content-Type': 'audio/mp4', 'Content-Length': String(data.length) }, body: data,
  }), environment)).status, 403);
});

test('invalid audio signature cannot be saved as a playable variant', async () => {
  const uploaded = new Map();
  const environment = { MEDIA_SIGNING_KEY: key, MEDIA_BUCKET: {
    head: async () => null,
    put: async (path, body) => {
      const bytes = new Uint8Array(await new Response(body).arrayBuffer());
      uploaded.set(path, bytes);
      return { size: bytes.length };
    },
    get: async path => ({
      body: new Blob([uploaded.get(path).slice(0, 12)]).stream(),
    }),
    delete: async path => { uploaded.delete(path); },
  } };
  const bogus = new Uint8Array(24).fill(7);
  const url = await ingestUrlFor(mediaId, 'AAC_256', 'audio/mp4', bogus.length);
  const response = await worker.fetch(new Request(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'audio/mp4', 'Content-Length': String(bogus.length) },
    body: bogus,
  }), environment);
  assert.equal(response.status, 422);
  assert.equal(uploaded.size, 0);
});

async function videoIngestUrlFor(assetId, size, expiry = Date.now() + 60_000) {
  const payload = `ingest:video:${assetId}:video/mp4:${size}:${expiry}`;
  const signingKey = await webcrypto.subtle.importKey(
    'raw', new TextEncoder().encode(key), { name: 'HMAC', hash: 'SHA-256' },
    false, ['sign'],
  );
  const signature = Buffer.from(await webcrypto.subtle.sign(
    'HMAC', signingKey, new TextEncoder().encode(payload),
  )).toString('base64url');
  return `https://media.breezze.test/ingest/video/${assetId}?b=${size}&e=${expiry}&s=${signature}`;
}

function ingestVideoBucket() {
  const stored = new Map();
  return {
    stored,
    async head(path) {
      const value = stored.get(path);
      return value ? { size: value.length } : null;
    },
    async put(path, body, options) {
      const value = new Uint8Array(await new Response(body).arrayBuffer());
      stored.set(path, value);
      return {
        size: value.length,
        httpMetadata: options.httpMetadata,
      };
    },
    async get(path, options = {}) {
      const value = stored.get(path);
      if (!value) return null;
      const selection = options.range
        ? value.slice(options.range.offset, options.range.offset + options.range.length)
        : value;
      return {
        size: value.length,
        httpEtag: '"video-test-etag"',
        httpMetadata: { contentType: 'video/mp4' },
        body: new Blob([selection]).stream(),
      };
    },
    async delete(path) { stored.delete(path); },
  };
}

test('video ingest requires signed PUT, validates MP4 magic and serves the same object', async () => {
  const bucket = ingestVideoBucket();
  const environment = { MEDIA_BUCKET: bucket, MEDIA_SIGNING_KEY: key };
  const data = new Uint8Array([
    0,0,0,16,102,116,121,112,105,115,111,109,0,0,0,0,1,2,3,4,
  ]);
  const ingestUrl = await videoIngestUrlFor(mediaId, data.length);
  const put = (url = ingestUrl, body = data, mime = 'video/mp4') =>
    new Request(url, {
      method: 'PUT',
      headers: { 'Content-Type': mime, 'Content-Length': String(body.length) },
      body,
    });
  assert.equal((await worker.fetch(put(), environment)).status, 201);
  const objectKey = `video/${mediaId}/original.mp4`;
  assert.deepEqual(bucket.stored.get(objectKey), data);
  assert.equal((await worker.fetch(put(), environment)).status, 409);
  const response = await worker.fetch(new Request(await videoUrlFor()), environment);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('Content-Type'), 'video/mp4');
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), data);
  assert.equal((await worker.fetch(put(ingestUrl.replace(/s=[^&]+/, 's=bad')), environment)).status, 403);
  assert.equal((await worker.fetch(put(ingestUrl.replace(mediaId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')), environment)).status, 403);
  assert.equal((await worker.fetch(put(await videoIngestUrlFor(mediaId, data.length, Date.now() - 5000)), environment)).status, 403);
  assert.equal((await worker.fetch(put(ingestUrl, data, 'audio/mp4'), environment)).status, 400);
});

test('video ingest rejects malformed bytes without leaving any R2 object', async () => {
  const bucket = ingestVideoBucket();
  const environment = { MEDIA_BUCKET: bucket, MEDIA_SIGNING_KEY: key };
  const fake = new Uint8Array(24).fill(17);
  const url = await videoIngestUrlFor(mediaId, fake.length);
  const result = await worker.fetch(new Request(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'video/mp4', 'Content-Length': String(fake.length) },
    body: fake,
  }), environment);
  assert.equal(result.status, 422);
  assert.equal(bucket.stored.size, 0);
});

test('allowlisted Flutter Web range access never bypasses signed media grants', async () => {
  const url = await urlFor();
  const configured = { ...env(), MEDIA_CORS_ORIGINS: 'https://app.breezze.example,https://preview.breezze.example' };
  const allowed = await worker.fetch(new Request(url, {
    headers: { Origin: 'https://app.breezze.example', Range: 'bytes=2-6' },
  }), configured);
  assert.equal(allowed.status, 206);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), 'https://app.breezze.example');
  assert.match(allowed.headers.get('Access-Control-Expose-Headers'), /Content-Range/);
  assert.deepEqual(new Uint8Array(await allowed.arrayBuffer()), bytes.slice(2, 7));

  const preflight = await worker.fetch(new Request(url, {
    method: 'OPTIONS', headers: { Origin: 'https://app.breezze.example' },
  }), configured);
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('Access-Control-Allow-Headers'), 'Range');

  const denied = await worker.fetch(new Request(url, {
    method: 'OPTIONS', headers: { Origin: 'https://untrusted.example' },
  }), configured);
  assert.equal(denied.status, 403);

  const forged = await worker.fetch(new Request(url.replace(/s=[^&]+/, 's=forged'), {
    headers: { Origin: 'https://app.breezze.example' },
  }), configured);
  assert.equal(forged.status, 403);
  assert.equal(forged.headers.get('Cache-Control'), 'no-store');

  const ingest = await videoIngestUrlFor(mediaId, 100);
  assert.equal((await worker.fetch(new Request(ingest, {
    method: 'OPTIONS', headers: { Origin: 'https://app.breezze.example' },
  }), configured)).status, 405);
});
