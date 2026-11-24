import { AudiusAdapter } from './audius.adapter';

describe('AudiusAdapter', () => {
  let originalFetch: typeof global.fetch;
  let originalEnabled: string | undefined;
  let originalCommercial: string | undefined;
  let adapter: AudiusAdapter;

  const publicTrack = () => ({
    id: 'V66vyPP', title: 'Original Artist Recording',
    duration: 212, user: { name: 'Original Artist', is_available: true },
    is_available: true, is_streamable: true, is_stream_gated: false,
    is_unlisted: false, is_delete: false, access: { stream: true },
    allowed_api_keys: null, access_authorities: null, stream_conditions: null,
    artwork: { '480x480': 'https://audius-nodes.com/test.jpg' },
    permalink: '/originalartist/original-recording',
  });
  const response = (data: unknown) => ({
    ok: true,
    json: async () => ({ data }),
  } as unknown as Response);
  beforeEach(() => {
    originalFetch = global.fetch;
    originalEnabled = process.env.AUDIUS_ENABLED;
    originalCommercial = process.env.BREEZZE_NONCOMMERCIAL;
    process.env.AUDIUS_ENABLED = 'true';
    process.env.BREEZZE_NONCOMMERCIAL = 'true';
    adapter = new AudiusAdapter();
    global.fetch = jest.fn().mockImplementation(async () =>
      response(publicTrack()));
  });
  afterEach(() => {
    global.fetch = originalFetch;
    if (originalEnabled == null) delete process.env.AUDIUS_ENABLED;
    else process.env.AUDIUS_ENABLED = originalEnabled;
    if (originalCommercial == null) delete process.env.BREEZZE_NONCOMMERCIAL;
    else process.env.BREEZZE_NONCOMMERCIAL = originalCommercial;
  });

  it('verifies artist OML API permission and attributes a free public stream', async () => {
    const check = await adapter.getAvailability('V66vyPP', 'TZ');
    expect(check).toMatchObject({
      kind: 'ok',
      value: { available: true },
      attribution: expect.stringContaining('Audius OML:'),
    });
    const proof = check.kind === 'ok' ? check.attribution ?? null : null;
    const resolved = await adapter.resolvePlayback({
      providerTrackId: 'V66vyPP',
      territory: 'TZ',
      authorization: {
        action: 'stream.full', expiresAt: null, attribution: proof,
      },
    });
    expect(resolved).toMatchObject({
      kind: 'ok',
      value: {
        url: 'https://api.audius.co/v1/tracks/V66vyPP/stream',
        mimeType: 'audio/mpeg',
      },
    });
    expect(adapter.capabilities.download).toBe(false);
    expect(check).toMatchObject({
      attribution: expect.stringContaining(
        'source https://audius.co/originalartist/original-recording',
      ),
    });
    // The resolver's fresh live permission check is sufficient for one
    // grant. No second call to Audius is needed just to format the URL.
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['artist disabled API stream', { is_streamable: false }],
    ['paid or otherwise gated stream', { is_stream_gated: true }],
    ['API permission not present', { access: { stream: false } }],
    ['unlisted track', { is_unlisted: true }],
    ['deleted track', { is_delete: true }],
    ['scheduled track', { is_scheduled_release: true }],
    ['wallet gate', { access_authorities: ['0x123'] }],
    ['restricted keys', { allowed_api_keys: ['secret-api-key'] }],
    ['conditional access', { stream_conditions: { country: 'US' } }],
    ['unavailable recording', { is_available: false }],
  ])('refuses %s', async (_, patch) => {
    global.fetch = jest.fn().mockResolvedValue(response({
      ...publicTrack(), ...patch,
    }));
    await expect(adapter.getAvailability('V66vyPP', 'TZ'))
      .resolves.toMatchObject({ kind: 'ok', value: { available: false } });
    await expect(adapter.resolvePlayback({
      providerTrackId: 'V66vyPP',
      territory: 'TZ',
      authorization: { action: 'stream.full', expiresAt: null, attribution: null },
    })).resolves.toMatchObject({
      kind: 'unsupported', reason: 'AUDIUS_OML_PUBLIC_STREAM_UNAVAILABLE',
    });
  });

  it('does not contact Audius when noncommercial configuration is not approved', async () => {
    process.env.BREEZZE_NONCOMMERCIAL = 'false';
    expect(adapter.enabled).toBe(false);
    await expect(adapter.getAvailability('V66vyPP', 'TZ'))
      .resolves.toMatchObject({ kind: 'unsupported' });
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('ignores malformed track IDs without making a network request', async () => {
    await expect(adapter.getAvailability('../secret', 'TZ'))
      .resolves.toMatchObject({ kind: 'error', code: 'AUDIUS_INVALID_TRACK_ID' });
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('discovery filters out gated songs before returning playable metadata', async () => {
    global.fetch = jest.fn().mockResolvedValue(response([
      publicTrack(), { ...publicTrack(), id: 'mRaOxp1', is_stream_gated: true },
    ]));
    const search = await adapter.search('original');
    expect(search).toMatchObject({
      kind: 'ok', value: [{ providerTrackId: 'V66vyPP' }],
    });
  });
});
