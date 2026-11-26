// Isolated audio-byte diagnostic. Only the CC-BY Blender Foundation video
// is used by default; no production playback, cookies or media persistence.
// This is an unofficial API compatibility test, not a licensing grant.
import { Innertube } from 'youtubei.js';

const id = process.env.BREEZZE_PROBE_VIDEO_ID || 'aqz-KE-bpKQ';
if (!/^[A-Za-z0-9_-]{11}$/.test(id)) throw new Error('Invalid probe video ID');
const verdict = {
  source: 'youtubei.js@18.3.0',
  videoId: id,
  sample: 'Big Buck Bunny / Blender Foundation / CC BY 3.0',
  metadata: false,
  playabilityStatus: null,
  infoKeys: [],
  audioFormat: false,
  playableAudioBytes: false,
  status: null,
  mediaType: null,
  bytesInspected: 0,
  failure: null,
};
const report = () => {
  // Never emit signed GoogleVideo URLs or request headers in CI logs.
  console.log('BREEZZE_AUDIO_PROBE=' + JSON.stringify(verdict));
};
const classify = (data) => {
  if (data.length >= 4 && data[0] === 0x1a && data[1] === 0x45 &&
      data[2] === 0xdf && data[3] === 0xa3) return 'webm';
  if (data.length >= 8 && new TextDecoder().decode(data.slice(4, 8)) === 'ftyp') return 'mp4';
  if (data.length >= 2 && data[0] === 0xff && (data[1] & 0xf0) === 0xf0) return 'aac';
  return null;
};
try {
  const client = await Innertube.create({ lang: 'en', location: 'US' });
  const info = await client.getBasicInfo(id);
  verdict.infoKeys = Object.keys(info ?? {}).filter(key =>
    ['basic_info', 'playability_status', 'streaming_data', 'captions',
      'current_video_endpoint', 'watch_next_feed'].includes(key));
  verdict.playabilityStatus = info?.playability_status?.status || null;
  // A 200 OK metadata request is not proof of video details nor audio.
  verdict.metadata = Boolean(info?.basic_info?.id === id ||
    info?.basic_info?.video_id === id || info?.basic_info?.title);
  // We still attempt a format lookup if the upstream omits videoDetails,
  // so the report differentiates blocked metadata from blocked audio.
  if (!info) throw new Error('NO_VIDEO_METADATA');
  const format = await client.getStreamingData(id, {
    type: 'audio', quality: 'best',
  });
  if (!format?.url) throw new Error('NO_AUDIO_STREAM_URL');
  const uri = new URL(format.url);
  if (uri.protocol !== 'https:' ||
      !(/(^|\.)googlevideo\.com$/.test(uri.hostname) ||
        /(^|\.)youtube\.com$/.test(uri.hostname))) {
    throw new Error('UNEXPECTED_AUDIO_CDN');
  }
  verdict.audioFormat = true;
  const response = await fetch(format.url, {
    headers: { Range: 'bytes=0-4095' },
    signal: AbortSignal.timeout(18000),
  });
  verdict.status = response.status;
  verdict.mediaType = response.headers.get('content-type')?.split(';')[0] || null;
  if (response.status !== 206 && response.status !== 200) {
    await response.body?.cancel();
    throw new Error('AUDIO_HTTP_' + response.status);
  }
  if (!response.body) throw new Error('EMPTY_AUDIO_BODY');
  const reader = response.body.getReader();
  let data = new Uint8Array(0);
  try {
    while (data.length < 4096) {
      const { done, value } = await reader.read();
      if (done) break;
      const next = new Uint8Array(Math.min(4096, data.length + value.length));
      next.set(data);
      next.set(value.subarray(0, next.length - data.length), data.length);
      data = next;
    }
  } finally {
    await reader.cancel().catch(() => {});
  }
  verdict.bytesInspected = data.length;
  verdict.container = classify(data);
  verdict.playableAudioBytes = data.length >= 64 &&
    verdict.container !== null &&
    (verdict.mediaType?.startsWith('audio/') || verdict.mediaType === 'application/octet-stream');
  if (!verdict.playableAudioBytes) throw new Error('NOT_VERIFIED_AUDIO_BYTES');
  report();
} catch (error) {
  // Errors may embed signed media URLs. Report only bounded diagnostics.
  verdict.failure = error instanceof Error
    ? (error.message.match(/^(NO_VIDEO_METADATA|NO_AUDIO_STREAM_URL|UNEXPECTED_AUDIO_CDN|AUDIO_HTTP_\d+|EMPTY_AUDIO_BODY|NOT_VERIFIED_AUDIO_BYTES)$/)
      ? error.message : error.name)
    : 'UNKNOWN_ERROR';
  report();
  process.exitCode = 1;
}
