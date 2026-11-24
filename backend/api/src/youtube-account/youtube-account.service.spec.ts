import { PrismaService } from '../prisma.service';
import { YoutubeAccountService } from './youtube-account.service';

describe('YoutubeAccountService owner-bound OAuth authorization', () => {
  const originalEnv = { ...process.env };
  const originalFetch = global.fetch;
  const userId = 'user-1';
  const channelId = 'UC' + 'x'.repeat(22);
  const accessToken = 'access_' + 'a'.repeat(50);
  const refreshToken = 'refresh_' + 'b'.repeat(50);

  const prisma = {
    youtubeAccountLinkFlow: {
      create: jest.fn(),
      findUnique: jest.fn(),
      updateMany: jest.fn(),
    },
    youtubeAccountConnection: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
      updateMany: jest.fn(),
      deleteMany: jest.fn(),
    },
    $transaction: jest.fn(),
  };
  let service: YoutubeAccountService;
  let requests: Array<{ url: string; init?: RequestInit }>;

  const response = (body: object, status = 200): Response =>
    ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    }) as Response;

  beforeEach(() => {
    jest.clearAllMocks();
    process.env.YOUTUBE_ACCOUNT_LINK_ENABLED = 'true';
    process.env.YOUTUBE_ACCOUNT_CLIENT_ID = 'client-123.apps.googleusercontent.com';
    process.env.YOUTUBE_ACCOUNT_CLIENT_SECRET = 'private-client-secret';
    process.env.YOUTUBE_ACCOUNT_REDIRECT_URI =
      'https://edge.breezze.test/api/v1/youtube-account/callback';
    process.env.YOUTUBE_ACCOUNT_TOKEN_KEY = Buffer.alloc(32, 9).toString('base64');
    requests = [];
    global.fetch = jest.fn(async (url: URL | string, init?: RequestInit) => {
      requests.push({ url: String(url), init });
      return response({});
    }) as typeof global.fetch;
    prisma.youtubeAccountLinkFlow.create.mockImplementation(async (args) =>
      ({ id: 'flow-1', expiresAt: args.data.expiresAt }));
    prisma.youtubeAccountLinkFlow.updateMany.mockResolvedValue({ count: 1 });
    prisma.youtubeAccountConnection.findUnique.mockResolvedValue(null);
    prisma.youtubeAccountConnection.upsert.mockResolvedValue({ userId });
    prisma.youtubeAccountConnection.updateMany.mockResolvedValue({ count: 1 });
    prisma.youtubeAccountConnection.deleteMany.mockResolvedValue({ count: 1 });
    prisma.$transaction.mockImplementation(async (callback) => callback(prisma));
    service = new YoutubeAccountService(prisma as unknown as PrismaService);
  });

  afterAll(() => {
    process.env = originalEnv;
    global.fetch = originalFetch;
  });

  afterEach(() => {
    process.env = { ...originalEnv };
    global.fetch = originalFetch;
  });

  it('refuses link flow without an explicitly enabled, securely configured consent client', async () => {
    delete process.env.YOUTUBE_ACCOUNT_LINK_ENABLED;
    await expect(service.start(userId)).rejects.toThrow('YOUTUBE_ACCOUNT_LINK_DISABLED');
    expect(prisma.youtubeAccountLinkFlow.create).not.toHaveBeenCalled();

    process.env.YOUTUBE_ACCOUNT_LINK_ENABLED = 'true';
    process.env.YOUTUBE_ACCOUNT_REDIRECT_URI =
      'http://attacker.test/api/v1/youtube-account/callback';
    await expect(service.start(userId)).rejects.toThrow('YOUTUBE_ACCOUNT_REDIRECT_INVALID');

    process.env.YOUTUBE_ACCOUNT_REDIRECT_URI =
      'https://edge.breezze.test/api/v1/youtube-account/callback';
    process.env.YOUTUBE_ACCOUNT_TOKEN_KEY = 'short';
    await expect(service.start(userId)).rejects.toThrow('YOUTUBE_ACCOUNT_LINK_NOT_CONFIGURED');
  });

  it('creates a state-bound, one-time read-only Google OAuth PKCE consent URL', async () => {
    const flow = await service.start(userId);
    const url = new URL(flow.authorizationUrl);

    expect(url.origin).toBe('https://accounts.google.com');
    expect(url.pathname).toBe('/o/oauth2/v2/auth');
    expect(url.searchParams.get('scope'))
      .toBe('https://www.googleapis.com/auth/youtube.readonly');
    expect(url.searchParams.get('access_type')).toBe('offline');
    expect(url.searchParams.get('prompt')).toBe('consent');
    expect(url.searchParams.get('code_challenge_method')).toBe('S256');
    expect(url.searchParams.get('code_challenge')).toMatch(/^[A-Za-z0-9_-]{43}$/);

    const saved = prisma.youtubeAccountLinkFlow.create.mock.calls[0][0].data;
    expect(saved.userId).toBe(userId);
    expect(saved.stateHash).not.toEqual(url.searchParams.get('state'));
    expect(saved.stateHash).toMatch(/^[0-9a-f]{64}$/);
    expect(saved.codeVerifier).toMatch(/^[A-Za-z0-9_-]{64}$/);
    expect(flow).not.toHaveProperty('codeVerifier');
    expect(flow).not.toHaveProperty('clientSecret');
    expect(flow).not.toHaveProperty('accessToken');
    expect(requests).toEqual([]);
  });

  async function beginConsent() {
    const started = await service.start(userId);
    const state = new URL(started.authorizationUrl).searchParams.get('state')!;
    const stored = prisma.youtubeAccountLinkFlow.create.mock.calls[0][0].data;
    prisma.youtubeAccountLinkFlow.findUnique.mockResolvedValue({
      id: 'flow-1', userId, stateHash: stored.stateHash,
      codeVerifier: stored.codeVerifier,
      status: 'pending', expiresAt: stored.expiresAt,
    });
    return { state };
  }

  function mockGoogleAuthorized() {
    global.fetch = jest.fn(async (url: URL | string, init?: RequestInit) => {
      requests.push({ url: String(url), init });
      if (String(url) === 'https://oauth2.googleapis.com/token') {
        return response({
          access_token: accessToken,
          refresh_token: refreshToken,
          expires_in: 3600,
          token_type: 'Bearer',
          scope: 'https://www.googleapis.com/auth/youtube.readonly',
        });
      }
      if (String(url).includes('youtube/v3/channels')) {
        return response({
          items: [{ id: channelId, snippet: { title: 'Owner YouTube Channel' } }],
        });
      }
      throw new Error('unexpected provider URL');
    }) as typeof global.fetch;
  }

  it('encrypts both tokens for one owner and never returns credentials in callback/status', async () => {
    const { state } = await beginConsent();
    mockGoogleAuthorized();
    expect(await service.callback(state, 'google-auth-code-123456')).toBe(true);
    const written = prisma.youtubeAccountConnection.upsert.mock.calls[0][0];
    expect(written.where).toEqual({ userId });
    expect(written.create.channelId).toBe(channelId);
    expect(written.create.accessTokenCiphertext).not.toContain(accessToken);
    expect(written.create.refreshTokenCiphertext).not.toContain(refreshToken);
    expect(written.create.accessTokenCiphertext.split('.')).toHaveLength(3);

    prisma.youtubeAccountConnection.findUnique.mockResolvedValueOnce({
      userId, channelId, channelTitle: 'Owner YouTube Channel',
      createdAt: new Date(),
    });
    const status = await service.status(userId);
    expect(status).toMatchObject({
      available: true, connected: true, channelId,
      scope: 'read_only_youtube_playlists',
    });
    expect(JSON.stringify(status)).not.toContain(accessToken);
    expect(JSON.stringify(status)).not.toContain(refreshToken);
    expect(requests[0].url).toBe('https://oauth2.googleapis.com/token');
    expect(requests[1].url).toContain('/youtube/v3/channels');
  });

  it('prevents OAuth replay, expired flow and reuse across existing owners', async () => {
    const { state } = await beginConsent();
    prisma.youtubeAccountLinkFlow.findUnique.mockResolvedValueOnce({
      status: 'completed', id: 'flow-1', expiresAt: new Date(Date.now() + 10000),
    });
    expect(await service.callback(state, 'code-from-user')).toBe(false);
    expect(requests).toHaveLength(0);

    const next = await beginConsent();
    mockGoogleAuthorized();
    prisma.youtubeAccountConnection.findUnique.mockResolvedValueOnce({
      userId: 'another-breezze-owner',
    });
    expect(await service.callback(next.state, 'google-auth-code-123456')).toBe(false);
    expect(prisma.youtubeAccountConnection.upsert).not.toHaveBeenCalled();
    expect(prisma.youtubeAccountLinkFlow.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'flow-1', status: 'processing' },
        data: expect.objectContaining({ status: 'failed' }),
      }),
    );
  });

  it('rejects missing read-only scope and never stores provider tokens', async () => {
    const { state } = await beginConsent();
    global.fetch = jest.fn(async () => response({
      access_token: accessToken,
      refresh_token: refreshToken,
      expires_in: 3600,
      token_type: 'Bearer',
      scope: 'openid email profile',
    })) as typeof global.fetch;
    expect(await service.callback(state, 'google-auth-code-123456')).toBe(false);
    expect(prisma.youtubeAccountConnection.upsert).not.toHaveBeenCalled();
  });

  it('reads a single page of the owning user playlists and does not expose OAuth secrets', async () => {
    const { state } = await beginConsent();
    mockGoogleAuthorized();
    expect(await service.callback(state, 'google-auth-code-123456')).toBe(true);
    const stored = prisma.youtubeAccountConnection.upsert.mock.calls[0][0].create;
    prisma.youtubeAccountConnection.findUnique.mockResolvedValue({
      ...stored, userId, channelId, channelTitle: 'Owner YouTube Channel',
    });
    global.fetch = jest.fn(async (url: URL | string, init?: RequestInit) => {
      requests.push({ url: String(url), init });
      return response({
        items: [
          { id: 'OLAK5uy_abcdefghij', snippet: {
              title: 'My YouTube playlist', thumbnails: {
                default: { url: 'https://i.ytimg.com/vi/thumb.jpg' },
              },
            },
            contentDetails: { itemCount: 8 } },
          { id: '../tamper', snippet: { title: 'Invalid playlist' } },
        ],
      });
    }) as typeof global.fetch;
    const data = await service.playlists(userId);
    expect(data).toMatchObject({
      source: 'youtube_data_api',
      scope: 'read_only_youtube_playlists',
      items: [{
        playlistId: 'OLAK5uy_abcdefghij', title: 'My YouTube playlist',
        trackCount: 8,
      }],
    });
    expect(data.items).toHaveLength(1);
    expect(JSON.stringify(data)).not.toContain(accessToken);
    expect(JSON.stringify(data)).not.toContain(refreshToken);
    expect(requests.at(-1)?.init?.headers).toEqual({
      Authorization: 'Bearer ' + accessToken,
    });
  });

  it('disconnects the current owner and invalidates unfinished link flows', async () => {
    const { state } = await beginConsent();
    mockGoogleAuthorized();
    expect(await service.callback(state, 'google-auth-code-123456')).toBe(true);
    const stored = prisma.youtubeAccountConnection.upsert.mock.calls[0][0].create;
    prisma.youtubeAccountConnection.findUnique.mockResolvedValue({
      refreshTokenCiphertext: stored.refreshTokenCiphertext,
    });
    const result = await service.disconnect(userId);
    expect(result).toEqual({ disconnected: true });
    expect(prisma.youtubeAccountLinkFlow.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId, status: { in: ['pending', 'processing'] } },
        data: expect.objectContaining({ status: 'cancelled' }),
      }),
    );
    expect(prisma.youtubeAccountConnection.deleteMany)
      .toHaveBeenCalledWith({ where: { userId } });
    expect(requests.at(-1)?.url).toBe('https://oauth2.googleapis.com/revoke');
  });
});
