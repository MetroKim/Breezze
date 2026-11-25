import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { createHmac, randomBytes, randomUUID } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';

function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      const port = typeof address === 'object' ? address.port : 0;
      server.close(() => resolve(port));
    });
  });
}

const port = await freePort();
const base = 'http://127.0.0.1:' + port;
const storageDir = mkdtempSync(join(tmpdir(), 'breezze-media-http-'));
const fixture = join(storageDir, 'test-tone.m4a');
const secret = randomBytes(48).toString('base64url');
const trackId = randomUUID();
const quality = 'AAC_256';
const mime = 'audio/mp4';

function signature(payload) {
  return createHmac('sha256', secret).update(payload).digest('base64url');
}

function grant(path, payload, expires) {
  return base + path + '?e=' + expires + '&s=' + signature(payload + ':' + expires);
}

function shortBody(res) {
  return res.text().then(text => text.slice(0, 180));
}

let processLog = '';
let worker;
try {
  // Original synthetic PCM tone, encoded as an AAC-in-MP4 recording.
  // This is not sourced from YouTube or another copyright catalogue.
  execFileSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-nostdin',
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2',
    '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart',
    '-y', fixture,
  ], { timeout: 30000 });
  const media = readFileSync(fixture);
  assert(media.length > 2000, 'AAC synthetic recording must be non-empty');
  assert.equal(media.subarray(4, 8).toString(), 'ftyp');
  const duration = Number(execFileSync('ffprobe', [
    '-v', 'error', '-show_entries', 'format=duration',
    '-of', 'default=noprint_wrappers=1:nokey=1', fixture,
  ], { encoding: 'utf8', timeout: 10000 }).trim());
  assert(duration >= 1.8 && duration <= 2.2, 'AAC fixture must decode');

  worker = spawn(join(process.cwd(), 'node_modules', '.bin', 'wrangler'), [
    'dev', '--local', '--ip', '127.0.0.1', '--port', String(port),
    '--persist-to', storageDir,
    '--var', 'MEDIA_SIGNING_KEY:' + secret,
  ], {
    cwd: process.cwd(),
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, WRANGLER_SEND_METRICS: 'false' },
  });
  for (const stream of [worker.stdout, worker.stderr]) {
    stream?.on('data', chunk => {
      processLog = (processLog + chunk.toString()).slice(-6000);
    });
  }
  let ready = false;
  for (let attempt = 0; attempt < 100; attempt++) {
    if (worker.exitCode !== null) break;
    try {
      const response = await fetch(base + '/health', { signal: AbortSignal.timeout(1200) });
      if (response.status === 200) { ready = true; break; }
    } catch { /* Local Worker not ready yet. */ }
    await new Promise(resolve => setTimeout(resolve, 350));
  }
  assert(ready, 'Wrangler local Worker failed to start');

  const ingestedAt = Date.now() + 120_000;
  const uploadPayload = ['ingest', trackId, quality, mime, media.length].join(':');
  const ingestUrl = base + '/ingest/audio/' + trackId + '/' + quality +
    '?b=' + media.length + '&m=' + encodeURIComponent(mime) +
    '&e=' + ingestedAt + '&s=' + signature(uploadPayload + ':' + ingestedAt);
  const put = await fetch(ingestUrl, {
    method: 'PUT',
    headers: { 'Content-Type': mime, 'Content-Length': String(media.length) },
    body: media,
  });
  assert.equal(put.status, 201, 'Synthetic AAC upload: ' + await shortBody(put));

  const expires = Date.now() + 90_000;
  const signed = grant('/audio/' + trackId + '/' + quality, trackId + ':' + quality, expires);
  const head = await fetch(signed, { method: 'HEAD' });
  assert.equal(head.status, 200, 'Signed media HEAD');
  assert.equal(Number(head.headers.get('content-length')), media.length);
  assert.equal(head.headers.get('content-type'), mime);

  const full = await fetch(signed);
  assert.equal(full.status, 200);
  assert.equal(full.headers.get('cache-control'), 'private, no-store');
  assert.deepEqual(Buffer.from(await full.arrayBuffer()), media);

  const seek = await fetch(signed, { headers: { Range: 'bytes=100-499' } });
  assert.equal(seek.status, 206);
  assert.equal(seek.headers.get('content-range'), 'bytes 100-499/' + media.length);
  assert.deepEqual(Buffer.from(await seek.arrayBuffer()), media.subarray(100, 500));

  const suffix = await fetch(signed, { headers: { Range: 'bytes=-101' } });
  assert.equal(suffix.status, 206);
  assert.deepEqual(Buffer.from(await suffix.arrayBuffer()), media.subarray(-101));

  const missingRange = await fetch(signed, { headers: { Range: 'bytes=999999-' } });
  assert.equal(missingRange.status, 416);
  assert.equal(missingRange.headers.get('content-range'), 'bytes */' + media.length);

  const download = grant('/audio/' + trackId + '/download', trackId + ':download', expires);
  const downloadResponse = await fetch(download);
  assert.equal(downloadResponse.status, 200);
  assert.match(downloadResponse.headers.get('content-disposition') || '', /attachment/);
  assert.deepEqual(Buffer.from(await downloadResponse.arrayBuffer()), media);

  const duplicate = await fetch(ingestUrl, {
    method: 'PUT', headers: { 'Content-Type': mime, 'Content-Length': String(media.length) },
    body: media,
  });
  assert.equal(duplicate.status, 409, 'Immutable variant overwrite must be rejected');

  const expired = grant('/audio/' + trackId + '/' + quality, trackId + ':' + quality, Date.now() - 1000);
  assert.equal((await fetch(expired)).status, 403);
  assert.equal((await fetch(signed.replace(/s=[^&]+/, 's=forged'))).status, 403);
  assert.equal((await fetch(base + '/audio/' + randomUUID() + '/' + quality)).status, 403);

  console.log('PASS: local workerd + R2 AAC ingest, HEAD, full playback, byte-range seek, download purpose and denial paths');
} catch (error) {
  console.error(String(error));
  console.error(processLog.replaceAll(secret, '[redacted]').slice(-2800));
  process.exitCode = 1;
} finally {
  if (worker?.pid) {
    try { process.kill(-worker.pid, 'SIGTERM'); } catch { /* Already stopped. */ }
  }
  rmSync(storageDir, { recursive: true, force: true });
}
