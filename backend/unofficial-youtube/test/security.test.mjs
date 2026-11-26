import test from 'node:test';
import assert from 'node:assert/strict';
import {
  experimentEnabled, allowlistedVideo, validSecret,
  safeAudioCdn, safeByteRange, validUpstreamRange,
} from '../src/security.mjs';

test('production never enables unofficial audio', () => {
  assert.equal(experimentEnabled({
    BREEZZE_INNERTUBE_AUDIO_EXPERIMENT: 'true', NODE_ENV: 'production',
  }), false);
  assert.equal(experimentEnabled({
    BREEZZE_INNERTUBE_AUDIO_EXPERIMENT: 'true',
    RAILWAY_ENVIRONMENT_NAME: 'production',
  }), false);
  assert.equal(experimentEnabled({
    BREEZZE_INNERTUBE_AUDIO_EXPERIMENT: 'true', NODE_ENV: 'test',
  }), true);
});
test('only explicitly allowlisted video IDs can use experimental player', () => {
  const env = { BREEZZE_AUDIO_TEST_ALLOWLIST: 'aqz-KE-bpKQ' };
  assert.equal(allowlistedVideo('aqz-KE-bpKQ', env), true);
  assert.equal(allowlistedVideo('x43OJXk8idI', env), false);
  assert.equal(allowlistedVideo('https://a.bc', env), false);
});
test('nontrivial internal token and fixed time comparison required', () => {
  const token = '12345678901234567890123456789012';
  assert.equal(validSecret(token, token), true);
  assert.equal(validSecret('a'.repeat(32), token), false);
  assert.equal(validSecret(token, ''), false);
});
test('HTTPS GoogleVideo only, never private network or redirect domains', () => {
  assert.equal(safeAudioCdn('https://r1---sn-a5mek.googlevideo.com/videoplayback?x=1'), true);
  assert.equal(safeAudioCdn('http://127.0.0.1:8080/music'), false);
  assert.equal(safeAudioCdn('https://googlevideo.com.attacker.test/audio'), false);
  assert.equal(safeAudioCdn('https://user:pass@googlevideo.com/a'), false);
});
test('single bounded HTTP range only', () => {
  assert.equal(safeByteRange('bytes=0-4095'), 'bytes=0-4095');
  assert.equal(safeByteRange('bytes=8000-'), 'bytes=8000-');
  assert.equal(safeByteRange('bytes=10-2'), false);
  assert.equal(safeByteRange('bytes=0-1,10-20'), false);
  assert.equal(safeByteRange(null), null);
});

test('206 response must match the exact requested seek offset and length', () => {
  assert.equal(validUpstreamRange('bytes=0-7', 'bytes 0-7/16', '8'), true);
  assert.equal(validUpstreamRange('bytes=8-', 'bytes 8-15/16', '8'), true);
  assert.equal(validUpstreamRange('bytes=0-7', 'bytes 8-15/16', '8'), false);
  assert.equal(validUpstreamRange('bytes=0-7', 'bytes 0-8/16', '9'), false);
  assert.equal(validUpstreamRange('bytes=0-7', 'bytes 0-7/16', '9'), false);
  assert.equal(validUpstreamRange('bytes=0-7', 'bytes 0-7/8', '8'), true);
  assert.equal(validUpstreamRange('bytes=0-7', 'bytes 0-8/8', '9'), false);
  assert.equal(validUpstreamRange('bytes=0-7', 'bytes 0-7/*', null), true);
  assert.equal(validUpstreamRange('bytes=0-7', null, '8'), false);
  assert.equal(validUpstreamRange('bytes=0-7', 'bytes 0-7/16', 'invalid'), false);
});
