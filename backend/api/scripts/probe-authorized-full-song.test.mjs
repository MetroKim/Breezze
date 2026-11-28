import test from 'node:test';
import assert from 'node:assert/strict';
import {
  decodeResponse, mustUrl, mediaHeaders, rangeParts, consumeAudio,
} from './probe-authorized-full-song.mjs';

test('QA parser unwraps Nest response envelope without assuming a grant', () => {
  assert.deepEqual(decodeResponse({ data: { items: [{ title: 'Test' }] } }),
    { items: [{ title: 'Test' }] });
  assert.deepEqual(decodeResponse({ items: [] }), { items: [] });
  assert.throws(() => decodeResponse(null), /QA_BAD_RESPONSE/);
});

test('rejects foreign/HTTP/credentialed media URL before any byte transfer', () => {
  assert.equal(mustUrl('https://qa.example.com/path', 'https://qa.example.com').pathname,
    '/path');
  assert.throws(() => mustUrl('https://evil.example/song', 'https://qa.example.com'),
    /QA_URL_NOT_APPROVED/);
  assert.throws(() => mustUrl('http://qa.example.com/song', 'https://qa.example.com'),
    /QA_URL_NOT_APPROVED/);
  assert.throws(() => mustUrl('https://user:pass@qa.example.com/song',
    'https://qa.example.com'), /QA_URL_NOT_APPROVED/);
  assert.throws(() => mustUrl('javascript:alert(1)', 'https://qa.example.com'),
    /QA_URL_NOT_APPROVED/);
});

test('strict HTTP audio MIME and 206 range validation', () => {
  assert.equal(mediaHeaders(new Response(null, {
    status: 206, headers: { 'content-type': 'audio/mpeg' },
  }), 206), 'audio/mpeg');
  assert.throws(() => mediaHeaders(new Response('<html/>'), 200),
    /QA_MEDIA_MIME_INVALID/);
  assert.throws(() => mediaHeaders(new Response(null, { status: 200 }), 206),
    /QA_MEDIA_STATUS_200/);
  assert.deepEqual(rangeParts('bytes 4096-8191/16384'),
    { start: 4096, end: 8191, size: 16384 });
  assert.throws(() => rangeParts('bytes 9999-9000/16384'),
    /QA_CONTENT_RANGE_INVALID/);
  assert.throws(() => rangeParts('bytes */16384'), /QA_CONTENT_RANGE_INVALID/);
});

test('bounded byte consumer counts actual delivered bytes, not metadata', async () => {
  const content = Uint8Array.from([0xff, 0xfb, 0x90, 0x64]);
  const response = new Response(content, {
    headers: { 'content-type': 'audio/mpeg' },
  });
  assert.equal(await consumeAudio(response, 4), 4);
  await assert.rejects(
    consumeAudio(new Response(content), 3),
    /QA_AUDIO_TOO_LARGE/,
  );
});
