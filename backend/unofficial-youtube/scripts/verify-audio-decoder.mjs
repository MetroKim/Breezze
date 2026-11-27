// End-to-end acceptance with genuinely decodable, original PCM audio.
// This runs entirely on 127.0.0.1: no YouTube requests, no third-party music.
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { createExperimentHandler } from '../src/handler.mjs';

const id = 'aqz-KE-bpKQ'; // allowlisted test ID; upstream is injected, not contacted
const token = 'local-generated-test-token-32-characters-or-more';
const env = {
  NODE_ENV: 'test',
  BREEZZE_INNERTUBE_AUDIO_EXPERIMENT: 'true',
  BREEZZE_AUDIO_TEST_ALLOWLIST: id,
  BREEZZE_INTERNAL_AUDIO_TEST_TOKEN: token,
};

// This WAV consists of 2 seconds of original 440-Hz PCM, NOT YouTube audio.
const samples = 16000;
const sampleRate = 8000;
const wav = Buffer.alloc(44 + samples * 2);
wav.write('RIFF', 0);
wav.writeUInt32LE(wav.length - 8, 4);
wav.write('WAVE', 8);
wav.write('fmt ', 12);
wav.writeUInt32LE(16, 16);
wav.writeUInt16LE(1, 20);
wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(sampleRate, 24);
wav.writeUInt32LE(sampleRate * 2, 28);
wav.writeUInt16LE(2, 32);
wav.writeUInt16LE(16, 34);
wav.write('data', 36);
wav.writeUInt32LE(samples * 2, 40);
for (let i = 0; i < samples; i++) {
  wav.writeInt16LE(Math.round(10000 * Math.sin(2 * Math.PI * 440 * i / sampleRate)),
    44 + i * 2);
}

const handler = createExperimentHandler({
  env,
  createClient: async () => ({
    getBasicInfo: async () => ({ playability_status: { status: 'OK' } }),
    getStreamingData: async () => ({
      url: 'https://r1---sn-test.googlevideo.com/videoplayback',
      mime_type: 'audio/wav',
    }),
  }),
  fetchAudio: async (_url, options) => {
    const match = /^bytes=(\d+)-(\d*)$/.exec(options.headers.Range || '');
    if (!match) {
      return new Response(wav, {
        status: 200,
        headers: {
          'Content-Type': 'audio/wav',
          'Content-Length': String(wav.length),
        },
      });
    }
    const start = Number(match[1]);
    if (start >= wav.length) throw new Error('Decoder requested out-of-range bytes');
    const end = match[2] ? Math.min(Number(match[2]), wav.length - 1) : wav.length - 1;
    const fragment = wav.subarray(start, end + 1);
    return new Response(fragment, {
      status: 206,
      headers: {
        'Content-Type': 'audio/wav',
        'Content-Length': String(fragment.length),
        'Content-Range': `bytes ${start}-${end}/${wav.length}`,
      },
    });
  },
});

const server = createServer(handler);
await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(0, '127.0.0.1', resolve);
});
try {
  const url = `http://127.0.0.1:${server.address().port}/v1/audio/${id}`;
  const ffmpeg = spawn('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-nostdin',
    '-headers', `Authorization: Bearer ${token}\r\n`,
    '-i', url,
    '-map', '0:a:0',
    '-f', 's16le', '-ac', '1', '-ar', String(sampleRate), '-',
  ], { stdio: ['ignore', 'pipe', 'pipe'] });

  const chunks = [];
  let total = 0;
  let diagnostic = '';
  ffmpeg.stdout.on('data', chunk => {
    total += chunk.length;
    if (total > 1_000_000) ffmpeg.kill('SIGKILL');
    else chunks.push(chunk);
  });
  ffmpeg.stderr.on('data', chunk => {
    diagnostic += chunk.toString().slice(0, 200);
  });
  const exitCode = await new Promise((resolve, reject) => {
    ffmpeg.once('error', reject);
    ffmpeg.once('close', resolve);
  });

  assert.equal(exitCode, 0, 'ffmpeg was unable to decode the original audio through HTTP');
  const pcm = Buffer.concat(chunks);
  assert.equal(pcm.length, samples * 2, 'Decoded WAV must be 2.0 seconds of mono PCM');
  const amplitudes = Array.from({ length: samples }, (_, i) => pcm.readInt16LE(i * 2));
  const peak = Math.max(...amplitudes.map(Math.abs));
  assert.ok(peak > 9000 && peak <= 10000, 'Decoded audio amplitude is incorrect');
  assert.equal(pcm.readInt16LE(0), 0);
  console.log(JSON.stringify({
    contract: 'BREEZZE_PCM_DECODE_ACCEPTANCE',
    result: 'PASS',
    source: 'original_generated_pcm',
    decoder: 'ffmpeg',
    durationSeconds: samples / sampleRate,
    sampleRate,
    decodedSamples: samples,
    rangedHttpTransport: true,
    actualYouTubeAudioVerified: false,
  }));
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
