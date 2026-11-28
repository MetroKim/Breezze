import { OpenSubsonicAdapter, safeOpenSubsonicOrigin } from './opensubsonic.adapter';

const envKeys = [
  'OPEN_SUBSONIC_ENABLED', 'OPEN_SUBSONIC_ORIGIN',
  'OPEN_SUBSONIC_API_KEY', 'OPEN_SUBSONIC_RELAY_SIGNING_KEY',
  'BREEZZE_PUBLIC_API_ORIGIN',
] as const;
const envBefore = Object.fromEntries(envKeys.map(k => [k, process.env[k]]));
const canonical = 'e85df20d-45f8-4a40-a271-e00b314a47d7';

function configure() {
  process.env.OPEN_SUBSONIC_ENABLED = 'true';
  process.env.OPEN_SUBSONIC_ORIGIN = 'https://music.partner.example';
  process.env.BREEZZE_PUBLIC_API_ORIGIN = 'https://api.breezze.example';
  process.env.OPEN_SUBSONIC_API_KEY = 'server-only-key-for-testing-123';
  process.env.OPEN_SUBSONIC_RELAY_SIGNING_KEY = 'a'.repeat(64);
}

const validSong = {
  'subsonic-response': {
    status: 'ok',
    song: {
      id: 'original-song', title: 'Full authorized master',
      artist: 'Original artist', duration: 238,
      contentType: 'audio/mpeg', isVideo: false,
    },
  },
};

describe('V8 opt-in OpenSubsonic full-song bridge', () => {
  const oldFetch = global.fetch;

  afterEach(() => {
    for (const key of envKeys) {
      const previous = envBefore[key];
      if (previous === undefined) delete process.env[key];
      else process.env[key] = previous;
    }
    global.fetch = oldFetch;
  });

  it('rejects insecure origins, embedded credentials, localhost and alternate ports', () => {
    expect(safeOpenSubsonicOrigin('http://music.example')).toBeNull();
    expect(safeOpenSubsonicOrigin('https://127.0.0.1')).toBeNull();
    expect(safeOpenSubsonicOrigin('https://localhost')).toBeNull();
    expect(safeOpenSubsonicOrigin('https://music.example:8080')).toBeNull();
    expect(safeOpenSubsonicOrigin('https://user:pass@music.example')).toBeNull();
    expect(safeOpenSubsonicOrigin('https://music.example/surprise')).toBeNull();
    expect(safeOpenSubsonicOrigin('https://music.example')).toBe('https://music.example');
  });

  it('fails closed by default and never produces a metadata-derived stream URL', async () => {
    for (const key of envKeys) delete process.env[key];
    const provider = new OpenSubsonicAdapter();
    expect(provider.enabled).toBe(false);
    expect(provider.capabilities.metadata).toBe(false);
    expect((await provider.getTrack('private-song')).kind).toBe('unsupported');
    expect((await provider.getAvailability('original-song', 'TZ')).kind).toBe('unsupported');
    expect((await provider.search('original-song')).kind).toBe('unsupported');
  });

  it('issues only a scoped, signed, short-lived Breezze URL with no upstream API key', async () => {
    configure();
    const upstream = jest.fn(async (url: URL) => {
      expect(url.origin).toBe('https://music.partner.example');
      expect(url.pathname).toBe('/rest/getSong.view');
      expect(url.searchParams.get('apiKey')).toBe(process.env.OPEN_SUBSONIC_API_KEY);
      return new Response(JSON.stringify(validSong), {
        headers: { 'content-type': 'application/json' },
      });
    });
    global.fetch = upstream as typeof fetch;
    const provider = new OpenSubsonicAdapter();
    expect(provider.enabled).toBe(true);
    expect((await provider.getAvailability('original-song', 'TZ')).kind).toBe('ok');

    const resolved = await provider.resolvePlayback({
      userId: 'tenantA', providerTrackId: 'original-song',
      canonicalTrackId: canonical, territory: 'TZ',
      authorization: { action: 'stream.full', expiresAt: null, attribution: null },
    });
    expect(resolved.kind).toBe('ok');
    if (resolved.kind !== 'ok') return;
    expect(resolved.value.url).toContain('https://api.breezze.example/api/v1/providers/opensubsonic/audio/original-song');
    expect(resolved.value.url).not.toContain('server-only-key');
    expect(resolved.value.mimeType).toBe('audio/mpeg');
    const token = new URL(resolved.value.url).searchParams.get('grant')!;
    expect(provider.verifyGrant(token, 'different-song')).toBeNull();
    const data = provider.verifyGrant(token, 'original-song');
    expect(data).toMatchObject({
      userId: 'tenantA', territory: 'TZ',
      canonicalTrackId: canonical, id: 'original-song',
    });
    expect(provider.verifyGrant(token + 'tamper', 'original-song')).toBeNull();
    expect(provider.verifyGrant('', 'original-song')).toBeNull();
  });

  it('will not turn a mismatched, video or absent song into playable audio', async () => {
    configure();
    global.fetch = jest.fn(async () => new Response(JSON.stringify({
      'subsonic-response': {
        status: 'ok', song: { ...validSong['subsonic-response'].song, isVideo: true },
      },
    }))) as typeof fetch;
    const provider = new OpenSubsonicAdapter();
    expect((await provider.getAvailability('original-song', 'TZ'))).toEqual({
      kind: 'ok', value: { available: false }, attribution: undefined,
    });
    expect((await provider.resolvePlayback({
      userId: 'tenantA', providerTrackId: 'original-song',
      canonicalTrackId: canonical, territory: 'TZ',
      authorization: { action: 'stream.full', expiresAt: null, attribution: null },
    })).kind).toBe('error');
  });

  it('rejects unauthorized or near-expired playback instead of emitting a URL', async () => {
    configure();
    const provider = new OpenSubsonicAdapter();
    const result = await provider.resolvePlayback({
      providerTrackId: 'original-song', canonicalTrackId: canonical, territory: 'TZ',
      authorization: { action: 'stream.full', expiresAt: null, attribution: null },
    });
    expect(result.kind).toBe('unsupported');
    const expired = provider.issueGrant({
      id: 'original-song', userId: 'tenantA', territory: 'TZ',
      canonicalTrackId: canonical, expires: Date.now() - 50,
    });
    expect(expired).toBeNull();
  });

  it('recognizes only binary audio with truthful 200/206 byte-range semantics', () => {
    const ok = new Response(new Uint8Array(1024), {
      status: 206,
      headers: { 'content-type': 'audio/mpeg', 'content-range': 'bytes 0-1023/5000' },
    });
    expect(OpenSubsonicAdapter.validMediaResponse(ok, true)).toBe(true);
    expect(OpenSubsonicAdapter.validMediaResponse(ok, false)).toBe(true);
    expect(OpenSubsonicAdapter.validMediaResponse(
      new Response('<html>login</html>', { headers: { 'content-type': 'text/html' } }), false,
    )).toBe(false);
    expect(OpenSubsonicAdapter.validMediaResponse(
      new Response(new Uint8Array(16), { headers: { 'content-type': 'audio/mpeg' } }), true,
    )).toBe(false);
  });
});
