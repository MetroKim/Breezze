import test from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

// Exercise the real Worker entrypoint, not a duplicate signature/range helper.
const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
}).outputText;
const { default: worker } = await import(
  'data:text/javascript;base64,' + Buffer.from(compiled).toString('base64')
);

const signingKey = 'breezze-media-worker-test-secret-32-bytes-long';
const trackId = '11111111-2222-3333-4444-555555555555';
const bytes = new TextEncoder().encode('ABCDEFGHIJKL');
const mimeType = 'audio/mp4';
const objectKey = 'audio/' + trackId + '/AAC_256';

function makeEnv(objects = new Map([[objectKey, bytes]])) {
  const head = (key) => {
    const data = objects.get(key);
    if (!data) return null;
    return {
      size: data.length,
      httpEtag: '"test-etag"',
      httpMetadata: { contentType: mimeType },
    };
  };
  return {
    MEDIA_SIGNING_KEY: signingKey,
    MEDIA_BUCKET: {
      async head(key) { return head(key); },
      async get(key, options) {
        const meta = head(key);
        if (!meta) return null;
        const source = objects.get(key);
        const ranged = options?.range
          ? source.slice(options.range.offset, options.range.offset + options.range.length)
          : source;
        return {
          ...meta,
          body: new ReadableStream({
            start(controller) { controller.enqueue(ranged); controller.close(); },
          }),
        };
      },
    },
  };
}

function signedUrl(variant = 'AAC_256', expires = Date.now() + 300_000) {
  const payload = trackId + ':' + variant + ':' + expires;
  const sig = createHmac('sha256', signingKey).update(payload).digest('base64url');
  return 'https://media.example/audio/' + trackId + '/' + variant +
    '?e=' + expires + '&s=' + sig;
}

test('GET returns signed private AAC bytes with no shared cache', async () => {
  const response = await worker.fetch(new Request(signedUrl()), makeEnv());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), mimeType);
  assert.equal(response.headers.get('cache-control'), 'private, no-store');
  assert.equal(response.headers.get('accept-ranges'), 'bytes');
  assert.equal(response.headers.get('content-length'), String(bytes.length));
  assert.equal(await response.text(), 'ABCDEFGHIJKL');
});

test('HEAD confirms object presence without delivering the body', async () => {
  const response = await worker.fetch(new Request(signedUrl(), { method: 'HEAD' }), makeEnv());
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-length'), String(bytes.length));
  assert.equal(await response.text(), '');
});

test('explicit and suffix byte ranges are correct for seeking', async () => {
  const env = makeEnv();
  let response = await worker.fetch(
    new Request(signedUrl(), { headers: { Range: 'bytes=4-7' } }), env,
  );
  assert.equal(response.status, 206);
  assert.equal(response.headers.get('content-range'), 'bytes 4-7/12');
  assert.equal(response.headers.get('content-length'), '4');
  assert.equal(await response.text(), 'EFGH');

  response = await worker.fetch(
    new Request(signedUrl(), { headers: { Range: 'bytes=-3' } }), env,
  );
  assert.equal(response.status, 206);
  assert.equal(response.headers.get('content-range'), 'bytes 9-11/12');
  assert.equal(await response.text(), 'JKL');

  response = await worker.fetch(
    new Request(signedUrl(), { headers: { Range: 'bytes=12-' } }), env,
  );
  assert.equal(response.status, 416);
  assert.equal(response.headers.get('content-range'), 'bytes */12');
});

test('rejects unsigned, expired and overlong capabilities', async () => {
  const env = makeEnv();
  const tampered = new URL(signedUrl());
  tampered.searchParams.set('s', 'not-the-signature');
  assert.equal((await worker.fetch(new Request(tampered), env)).status, 403);

  assert.equal((await worker.fetch(
    new Request(signedUrl('AAC_256', Date.now() - 1000)), env,
  )).status, 403);

  assert.equal((await worker.fetch(
    new Request(signedUrl('AAC_256', Date.now() + 8 * 60 * 60 * 1000)), env,
  )).status, 403);

  assert.equal((await worker.fetch(
    new Request(signedUrl('download')), env,
  )).status, 200); // the download purpose maps to the verified AAC_256 object
});

test('never serves an absent internal recording', async () => {
  const response = await worker.fetch(
    new Request(signedUrl()), makeEnv(new Map()),
  );
  assert.equal(response.status, 404);
});

test('health reports binding configuration only, not actual media availability', async () => {
  const env = makeEnv(new Map());
  const response = await worker.fetch(new Request('https://media.example/health'), env);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: 'configured', service: 'breezze-media',
  });
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal((await worker.fetch(
    new Request('https://media.example/health', { method: 'HEAD' }), env,
  )).status, 200);
});
