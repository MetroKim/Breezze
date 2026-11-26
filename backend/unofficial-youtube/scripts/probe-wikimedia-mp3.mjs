/**
 * Confirm cross-platform MP3 transcode of Keith Adler's real, public-domain
 * full song. Stream proof, not YouTube or Audius.
 */
import { spawn } from 'node:child_process';

const source = 'https://upload.wikimedia.org/wikipedia/commons/transcoded/1/1f/Promise.ogg/Promise.ogg.mp3';
const ua = 'BreezzeAudioAcceptance/1.0 (https://github.com/MetroKim/Breezze)';
const report = {
  source: 'Wikimedia Commons',
  title: 'Promise',
  artist: 'Keith Adler',
  codec: 'mp3_transcode',
  status: null, hasMp3Header: false, bytes: 0, decodedPcmBytes: 0,
  decoded: false, verifiedDurationSeconds: null,
  midpointDecodedPcmBytes: 0, midpointSeekPassed: false, failure: null,
};
try {
  const response = await fetch(source, {
    headers: { 'User-Agent': ua, Range: 'bytes=0-16383' },
    signal: AbortSignal.timeout(25000),
  });
  report.status = response.status;
  if (![200, 206].includes(response.status)) throw Error('HTTP_' + response.status);
  const reader = response.body.getReader();
  const { value } = await reader.read();
  await reader.cancel().catch(() => {});
  report.bytes = value?.length ?? 0;
  const signature = value && value.length >= 3
    ? new TextDecoder().decode(value.subarray(0, 3)) : '';
  const sync = value && value.length >= 2 && value[0] === 0xff &&
    (value[1] & 0xe0) === 0xe0;
  report.hasMp3Header = signature === 'ID3' || sync;
  if (!report.hasMp3Header) throw Error('NOT_MP3');
  const ff = spawn('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-nostdin',
    '-user_agent', ua, '-i', source,
    '-t', '8', '-vn', '-ac', '1', '-ar', '16000',
    '-acodec', 'pcm_s16le', '-f', 's16le', 'pipe:1',
  ], { stdio: ['ignore','pipe','pipe'] });
  const deadline = setTimeout(() => ff.kill('SIGKILL'), 65000);
  ff.stdout.on('data', b => { report.decodedPcmBytes += b.length; });
  const exit = await new Promise((resolve,reject) => {
    ff.once('close', resolve); ff.once('error', reject);
  });
  clearTimeout(deadline);
  report.decoded = exit === 0 && report.decodedPcmBytes >= 240000;
  if (!report.decoded) throw Error('MP3_DECODE_UNAVAILABLE');

  // Probe metadata duration from actual remote MP3, not from our fixture.
  const probe = spawn('ffprobe', [
    '-v', 'error', '-user_agent', ua,
    '-show_entries', 'format=duration',
    '-of', 'default=noprint_wrappers=1:nokey=1',
    source,
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  let durationText = '';
  probe.stdout.on('data', b => { durationText += b.toString().slice(0, 100); });
  const probeTimer = setTimeout(() => probe.kill('SIGKILL'), 65000);
  const probeExit = await new Promise((resolve,reject) => {
    probe.once('close', resolve); probe.once('error', reject);
  });
  clearTimeout(probeTimer);
  report.verifiedDurationSeconds = Number.parseFloat(durationText);
  if (probeExit !== 0 || !(report.verifiedDurationSeconds > 140 &&
                             report.verifiedDurationSeconds < 155)) {
    throw Error('FULL_DURATION_UNAVAILABLE');
  }

  // Actual seek into the second minute. Decode to PCM, never save a copy.
  const midpoint = spawn('ffmpeg', [
    '-hide_banner', '-loglevel', 'error', '-nostdin',
    '-ss', '60', '-user_agent', ua, '-i', source,
    '-t', '8', '-vn', '-ac', '1', '-ar', '16000',
    '-acodec', 'pcm_s16le', '-f', 's16le', 'pipe:1',
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  const midpointTimer = setTimeout(() => midpoint.kill('SIGKILL'), 65000);
  midpoint.stdout.on('data', b => { report.midpointDecodedPcmBytes += b.length; });
  const midpointExit = await new Promise((resolve,reject) => {
    midpoint.once('close', resolve); midpoint.once('error', reject);
  });
  clearTimeout(midpointTimer);
  report.midpointSeekPassed = midpointExit === 0 &&
    report.midpointDecodedPcmBytes >= 240000;
  if (!report.midpointSeekPassed) throw Error('MIDPOINT_SEEK_UNAVAILABLE');
} catch (error) {
  report.failure = error instanceof Error && /^(HTTP_\d+|NOT_MP3|MP3_DECODE_UNAVAILABLE|FULL_DURATION_UNAVAILABLE|MIDPOINT_SEEK_UNAVAILABLE)$/.test(error.message)
    ? error.message : error?.name || 'UnknownError';
}
console.log('BREEZZE_WIKIMEDIA_MP3_PROBE=' + JSON.stringify(report));
if (!report.decoded || !report.midpointSeekPassed) process.exitCode = 1;
