/**
 * Independent live audio acceptance with a REAL full-length, public-domain
 * composition. Uses Wikimedia's original file (not YouTube, not Audius).
 * Verifies actual remote Ogg bytes and PCM decode, no stored downloads.
 * Source/rights: https://commons.wikimedia.org/wiki/File:Promise.ogg
 * Artist Keith Adler, original full track 148.2 seconds, PD-self.
 */
import { spawn } from 'node:child_process';

const SOURCE = 'https://upload.wikimedia.org/wikipedia/commons/1/1f/Promise.ogg';
const USER_AGENT = 'BreezzeAudioAcceptance/1.0 (https://github.com/MetroKim/Breezze)';
const result = {
  type: 'real_public_domain_song',
  title: 'Promise',
  artist: 'Keith Adler',
  source: 'Wikimedia Commons',
  license: 'Public domain (PD-self)',
  testWindowSeconds: 8,
  rangeHttpStatus: null,
  header: null,
  decodedPcmBytes: 0,
  decodePassed: false,
  externalYouTubeAudioVerified: false,
  failure: null,
};
function print() {
  // Do not emit any signed URLs, cookies, or raw response headers.
  console.log('BREEZZE_REAL_SONG_PROBE=' + JSON.stringify(result));
}
try {
  const response = await fetch(SOURCE, {
    headers: {
      'User-Agent': USER_AGENT,
      Range: 'bytes=0-65535',
      Accept: 'application/ogg, audio/ogg',
    },
    signal: AbortSignal.timeout(25000),
  });
  result.rangeHttpStatus = response.status;
  if (![200, 206].includes(response.status)) {
    await response.body?.cancel();
    throw Error('AUDIO_HTTP_' + response.status);
  }
  if (!response.body) throw Error('EMPTY_AUDIO_BODY');
  const reader = response.body.getReader();
  let data = new Uint8Array(0);
  try {
    while (data.length < 64) {
      const chunk = await reader.read();
      if (chunk.done) break;
      const next = new Uint8Array(Math.min(64, data.length + chunk.value.length));
      next.set(data);
      next.set(chunk.value.subarray(0, next.length - data.length), data.length);
      data = next;
    }
  } finally { await reader.cancel().catch(() => {}); }
  result.header = data.length >= 4 ? new TextDecoder().decode(data.slice(0, 4)) : null;
  if (result.header !== 'OggS') throw Error('NOT_OGG_AUDIO');

  const ffmpeg = spawn('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-nostdin',
    '-user_agent', USER_AGENT,
    '-i', SOURCE,
    '-t', String(result.testWindowSeconds),
    '-vn', '-acodec', 'pcm_s16le', '-ac', '1', '-ar', '16000',
    '-f', 's16le', 'pipe:1',
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  const guard = setTimeout(() => ffmpeg.kill('SIGKILL'), 65000);
  let stderr = '';
  ffmpeg.stdout.on('data', buf => { result.decodedPcmBytes += buf.length; });
  ffmpeg.stderr.on('data', buf => { stderr += buf.toString().slice(0, 200); });
  const exit = await new Promise((resolve, reject) => {
    ffmpeg.once('error', reject);
    ffmpeg.once('close', resolve);
  });
  clearTimeout(guard);
  // 8 seconds * 16,000 samples/s * 2 bytes/sample = 256,000 PCM bytes.
  result.decodePassed = exit === 0 && result.decodedPcmBytes >= 248000;
  if (!result.decodePassed) throw Error('REMOTE_DECODE_FAILED');
  print();
} catch (err) {
  const known = /^(AUDIO_HTTP_\\d+|EMPTY_AUDIO_BODY|NOT_OGG_AUDIO|REMOTE_DECODE_FAILED)$/;
  result.failure = err instanceof Error
    ? (known.test(err.message) ? err.message : err.name)
    : 'UNKNOWN_ERROR';
  print();
  process.exitCode = 1;
}
