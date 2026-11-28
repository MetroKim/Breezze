import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
import { createHmac, randomBytes, randomUUID } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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

  // Two simultaneous valid upload grants must never replace each other's R2 bytes.
  const raceId = randomUUID();
  const raceExpiry = Date.now() + 120_000;
  const racePayload = ['ingest', raceId, quality, mime, media.length, raceExpiry].join(':');
  const raceUrl = base + '/ingest/audio/' + raceId + '/' + quality +
    '?b=' + media.length + '&m=' + encodeURIComponent(mime) +
    '&e=' + raceExpiry + '&s=' + signature(racePayload);
  const raceUpload = () => fetch(raceUrl, {
    method: 'PUT',
    headers: { 'Content-Type': mime, 'Content-Length': String(media.length) },
    body: media,
  });
  const race = await Promise.all([raceUpload(), raceUpload()]);
  assert.deepEqual(race.map(r => r.status).sort(), [201, 409],
    'Concurrent ingest must have exactly one immutable winner');

  // Video rights-path acceptance: an original H.264/AAC MP4 travels
  // through signed ingest -> local Worker/R2 -> byte-preserving playback.
  // No commercial recording or unofficial YouTube source is involved.
  const videoFixture = join(storageDir, 'breezze-original-test-video.mp4');
  execFileSync('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-nostdin',
    '-f', 'lavfi', '-i', 'testsrc2=size=64x64:rate=8:duration=4',
    '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=16000:duration=4',
    '-t', '4', '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
    '-profile:v', 'baseline', '-preset', 'ultrafast', '-crf', '35',
    '-c:a', 'aac', '-b:a', '24k', '-movflags', '+faststart',
    '-y', videoFixture,
  ], { timeout: 30000 });
  const videoBytes = readFileSync(videoFixture);
  assert(videoBytes.length > 2048, 'Original MP4 fixture must be non-empty');
  assert.equal(videoBytes.subarray(4, 8).toString(), 'ftyp');

  const videoId = randomUUID();
  const videoExpires = Date.now() + 120_000;
  const videoIngestPayload =
    'ingest:video:' + videoId + ':video/mp4:' + videoBytes.length + ':' + videoExpires;
  const videoIngest = base + '/ingest/video/' + videoId +
    '?b=' + videoBytes.length + '&e=' + videoExpires +
    '&s=' + signature(videoIngestPayload);
  const videoPut = await fetch(videoIngest, {
    method: 'PUT',
    headers: { 'Content-Type': 'video/mp4',
               'Content-Length': String(videoBytes.length) },
    body: videoBytes,
  });
  assert.equal(videoPut.status, 201, 'Video ingest: ' + await shortBody(videoPut));

  const videoStream = grant('/video/' + videoId + '/stream',
    'video:' + videoId + ':stream', videoExpires);
  const videoHead = await fetch(videoStream, { method: 'HEAD' });
  assert.equal(videoHead.status, 200, 'Signed video HEAD');
  assert.equal(videoHead.headers.get('content-type'), 'video/mp4');
  assert.equal(Number(videoHead.headers.get('content-length')), videoBytes.length);
  assert.equal(videoHead.headers.get('accept-ranges'), 'bytes');

  const videoFull = await fetch(videoStream);
  assert.equal(videoFull.status, 200);
  assert.equal(videoFull.headers.get('cache-control'), 'private, no-store');
  const videoDelivered = Buffer.from(await videoFull.arrayBuffer());
  assert.deepEqual(videoDelivered, videoBytes, 'Full video must be byte exact');
  const deliveredFile = join(storageDir, 'breezze-video-delivered.mp4');
  writeFileSync(deliveredFile, videoDelivered);
  const playableSeconds = Number(execFileSync('ffprobe', [
    '-v', 'error', '-show_entries', 'format=duration',
    '-of', 'default=noprint_wrappers=1:nokey=1', deliveredFile,
  ], { encoding: 'utf8', timeout: 15000 }).trim());
  assert(playableSeconds > 3 && playableSeconds < 5,
    'Video delivered via R2 must decode for the full recording');

  const videoSeek = await fetch(videoStream, {
    headers: { Range: 'bytes=128-1023' },
  });
  assert.equal(videoSeek.status, 206);
  assert.equal(videoSeek.headers.get('content-range'),
    'bytes 128-1023/' + videoBytes.length);
  assert.deepEqual(Buffer.from(await videoSeek.arrayBuffer()),
    videoBytes.subarray(128, 1024));

  const videoTail = await fetch(videoStream, {
    headers: { Range: 'bytes=-256' },
  });
  assert.equal(videoTail.status, 206);
  assert.deepEqual(Buffer.from(await videoTail.arrayBuffer()),
    videoBytes.subarray(-256));

  const staleVideoValidator = await fetch(videoStream, {
    headers: { Range: 'bytes=0-511', 'If-Range': '"old-video-etag"' },
  });
  assert.equal(staleVideoValidator.status, 200,
    'Stale video validator must fetch the entire asset');
  assert.deepEqual(Buffer.from(await staleVideoValidator.arrayBuffer()), videoBytes);

  const videoUnsatisfiable = await fetch(videoStream, {
    headers: { Range: 'bytes=999999999-' },
  });
  assert.equal(videoUnsatisfiable.status, 416);
  assert.equal(videoUnsatisfiable.headers.get('content-range'),
    'bytes */' + videoBytes.length);
  assert.equal((await fetch(videoStream.replace(/s=[^&]+/, 's=forged'))).status, 403);
  assert.equal((await fetch(grant('/video/' + videoId + '/stream',
    'video:' + videoId + ':stream', Date.now() - 1000))).status, 403);
  assert.equal((await fetch(base + '/video/' + videoId + '/download' +
    new URL(videoStream).search)).status, 403,
    'Stream authorization must not grant video downloading');

  const videoDownloadUrl = grant('/video/' + videoId + '/download',
    'video:' + videoId + ':download', videoExpires);
  const videoDownload = await fetch(videoDownloadUrl);
  assert.equal(videoDownload.status, 200);
  assert.match(videoDownload.headers.get('content-disposition') || '',
    /attachment; filename="breezze-video.mp4"/);
  assert.deepEqual(Buffer.from(await videoDownload.arrayBuffer()), videoBytes);

  const videoDuplicate = await fetch(videoIngest, {
    method: 'PUT',
    headers: { 'Content-Type': 'video/mp4',
               'Content-Length': String(videoBytes.length) },
    body: videoBytes,
  });
  assert.equal(videoDuplicate.status, 409,
    'Uploaded MP4 must never overwrite an existing object');

  console.log('PASS: local Worker/R2 signed H.264 MP4 ingest, full original video delivery, ffprobe duration, HEAD, HTTP 206 seeks, 416, expiry and purpose isolation');

  console.log('PASS: real local workerd/R2 AAC HTTP ingest, HEAD, seek, purpose-bound grants and atomic uploads');
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
