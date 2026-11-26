import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createExperimentHandler } from '../src/handler.mjs';

const id = 'aqz-KE-bpKQ';
const sampleUrl = 'https://r1---sn-x.googlevideo.com/videoplayback?expire=9999999999';
const token = 'this-is-a-32-byte-test-only-internal-token';
const safeEnv = {
  NODE_ENV: 'test',
  BREEZZE_INNERTUBE_AUDIO_EXPERIMENT: 'true',
  BREEZZE_AUDIO_TEST_ALLOWLIST: id,
  BREEZZE_INTERNAL_AUDIO_TEST_TOKEN: token,
};
const fixture = Uint8Array.from([
  0x1a, 0x45, 0xdf, 0xa3, 0x9f, 0x42, 0x86, 0x81,
  0x01, 0x42, 0xf7, 0x81, 0x01, 0x42, 0xf2, 0x81,
]);

async function request(handlerOptions, route = '/v1/audio/' + id, headers = {}) {
  const server = createServer(createExperimentHandler(handlerOptions));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const port = server.address().port;
    const response = await fetch('http://127.0.0.1:' + port + route, {
      headers,
    });
    const data = new Uint8Array(await response.arrayBuffer());
    return { status: response.status, headers: response.headers, data };
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}
function handlerOptions({ env = safeEnv, status = 'OK', url = sampleUrl,
                          fetchAudio } = {}) {
  return {
    env,
    createClient: async () => ({
      getBasicInfo: async () => ({ playability_status: { status } }),
      getStreamingData: async () => ({
        url,
        mime_type: 'audio/webm',
      }),
    }),
    fetchAudio: fetchAudio || (async () => new Response(fixture, {
      status: 200, headers: {
        'content-type': 'audio/webm',
        'content-length': String(fixture.length),
      },
    })),
  };
}
function authHeaders(extra = {}) {
  return { Authorization: 'Bearer ' + token, ...extra };
}

test('no valid token: forbidden before any upstream API call', async () => {
  let calls = 0;
  const options = {
    env: safeEnv,
    createClient: async () => {
      calls++;
      throw new Error('must not be called');
    },
  };
  const denied = await request(options);
  assert.equal(denied.status, 403);
  assert.equal(calls, 0);
  const allowed = await request(handlerOptions(), '/health');
  assert.equal(allowed.status, 200);
  assert.match(new TextDecoder().decode(allowed.data), /"enabled":true/);
});

test('production is never accessible even with matching secret and ID', async () => {
  const result = await request(handlerOptions({
    env: { ...safeEnv, NODE_ENV: 'production' },
  }), '/v1/audio/' + id, authHeaders());
  assert.equal(result.status, 403);
});

test('unapproved track cannot reach upstream', async () => {
  const result = await request(handlerOptions(),
    '/v1/audio/x43OJXk8idI', authHeaders());
  assert.equal(result.status, 403);
});

test('LOGIN_REQUIRED remains 422 instead of fabricated audio', async () => {
  let invoked = false;
  const options = handlerOptions({
    status: 'LOGIN_REQUIRED',
    fetchAudio: async () => { invoked = true; throw new Error('bad'); },
  });
  const result = await request(options, '/v1/audio/' + id, authHeaders());
  assert.equal(result.status, 422);
  assert.equal(invoked, false);
});

test('permitted test source pipes real response bytes and never signed source URL', async () => {
  const result = await request(handlerOptions(), '/v1/audio/' + id, authHeaders());
  assert.equal(result.status, 200);
  assert.equal(result.headers.get('content-type'), 'audio/webm');
  assert.equal(result.headers.get('cache-control'), 'private, no-store, max-age=0');
  assert.deepEqual(result.data, fixture);
  assert.equal(result.headers.get('location'), null);
});

test('HTTP Range 206 is transmitted with exact byte content and metadata', async () => {
  let receivedRange;
  const options = handlerOptions({
    fetchAudio: async (_url, options) => {
      receivedRange = options.headers.Range;
      return new Response(fixture.slice(0, 8), {
        status: 206,
        headers: {
          'content-type': 'audio/webm',
          'content-length': '8',
          'content-range': 'bytes 0-7/16',
        },
      });
    },
  });
  const result = await request(options, '/v1/audio/' + id,
    authHeaders({ Range: 'bytes=0-7' }));
  assert.equal(receivedRange, 'bytes=0-7');
  assert.equal(result.status, 206);
  assert.equal(result.headers.get('content-range'), 'bytes 0-7/16');
  assert.deepEqual(result.data, fixture.slice(0, 8));
});

test('unsafe URL, invalid ranges and HTML responses are not media', async () => {
  const invalidUrl = await request(handlerOptions({
    url: 'https://googlevideo.com.attacker.com/media',
  }), '/v1/audio/' + id, authHeaders());
  assert.equal(invalidUrl.status, 422);

  const invalidRange = await request(handlerOptions(),
    '/v1/audio/' + id, authHeaders({ Range: 'bytes=0-2,3-4' }));
  assert.equal(invalidRange.status, 416);

  const html = await request(handlerOptions({
    fetchAudio: async () => new Response('<html>blocked</html>', {
      headers: { 'content-type': 'text/html' },
    }),
  }), '/v1/audio/' + id, authHeaders());
  assert.equal(html.status, 502);
});

test('range cannot silently degrade to whole-file 200', async () => {
  const missing206 = await request(handlerOptions(),
    '/v1/audio/' + id, authHeaders({ Range: 'bytes=0-7' }));
  assert.equal(missing206.status, 502);

  const missingContentRange = await request(handlerOptions({
    fetchAudio: async () => new Response(fixture.slice(0, 8), {
      status: 206, headers: { 'content-type': 'audio/webm' },
    }),
  }), '/v1/audio/' + id, authHeaders({ Range: 'bytes=0-7' }));
  assert.equal(missingContentRange.status, 502);
});

test('rejects upstream 206 if Content-Range does not match requested seek', async () => {
  const wrongOffset = await request(handlerOptions({
    fetchAudio: async () => new Response(fixture.slice(0, 8), {
      status: 206,
      headers: {
        'content-type': 'audio/webm',
        'content-length': '8',
        'content-range': 'bytes 8-15/16',
      },
    }),
  }), '/v1/audio/' + id, authHeaders({ Range: 'bytes=0-7' }));
  assert.equal(wrongOffset.status, 502);
});

test('rejects transformed HTTP content-encoding for byte-exact playback', async () => {
  const compressed = await request(handlerOptions({
    fetchAudio: async () => new Response(fixture, {
      status: 200,
      headers: {
        'content-type': 'audio/webm',
        'content-encoding': 'gzip',
      },
    }),
  }), '/v1/audio/' + id, authHeaders());
  assert.equal(compressed.status, 502);
});

test('upstream audio request explicitly disables transfer compression', async () => {
  let compressionHeader;
  const result = await request(handlerOptions({
    fetchAudio: async (_url, options) => {
      compressionHeader = options.headers['Accept-Encoding'];
      return new Response(fixture, {
        status: 200,
        headers: { 'content-type': 'audio/webm' },
      });
    },
  }), '/v1/audio/' + id, authHeaders());
  assert.equal(result.status, 200);
  assert.equal(compressionHeader, 'identity');
});
