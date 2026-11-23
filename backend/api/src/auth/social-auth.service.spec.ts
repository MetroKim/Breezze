import {
  createHash, generateKeyPairSync, randomBytes, sign,
} from 'node:crypto';
import {
  ConflictException, ServiceUnavailableException, UnauthorizedException,
} from '@nestjs/common';
import { SocialAuthService } from './social-auth.service';

const config = {
  GOOGLE_OAUTH_CLIENT_ID: 'breezze-google-test-client',
  GOOGLE_OAUTH_CLIENT_SECRET: 'server-only-test-secret',
  GOOGLE_OAUTH_REDIRECT_URI:
    'https://api.breezze.example/api/v1/auth/social/callback/google',
  JWT_SECRET: 'test-social-jwt-encryption-secret-value-at-least-32-bytes',
};

describe('Social OAuth safety and cross-platform pairing', () => {
  const prisma = {
    socialLoginFlow: {
      create: jest.fn(),
      findUnique: jest.fn(),
      updateMany: jest.fn(),
      update: jest.fn(),
    },
    socialAuthIdentity: { findUnique: jest.fn() },
    user: { findFirst: jest.fn(), create: jest.fn() },
  };
  const auth = { issueVerifiedSocialSession: jest.fn() };
  let social: SocialAuthService;
  const previous: Record<string, string | undefined> = {};
  let originalFetch: typeof fetch;

  beforeAll(() => {
    for (const [key, value] of Object.entries(config)) {
      previous[key] = process.env[key];
      process.env[key] = value;
    }
  });
  afterAll(() => {
    for (const key of Object.keys(config)) {
      if (previous[key] === undefined) delete process.env[key];
      else process.env[key] = previous[key];
    }
  });
  beforeEach(() => {
    jest.clearAllMocks();
    originalFetch = global.fetch;
    social = new SocialAuthService(prisma as any, auth as any);
  });
  afterEach(() => { global.fetch = originalFetch; });

  it('only enables providers when server-side OAuth credentials exist', () => {
    expect(social.providers()).toEqual({ google: true, apple: false });
    expect(() => (social as any).config('apple')).toThrow(
      ServiceUnavailableException,
    );
  });

  it('starts with random verifier, hashed state and app-only pairing secret', async () => {
    prisma.socialLoginFlow.create.mockImplementation(({data}: any) =>
      Promise.resolve({
        id: 'd1a7fd75-83f5-4e52-917d-082b25643bb9',
        expiresAt: data.expiresAt,
      }),
    );
    const first = await social.start('google');
    const second = await social.start('google');
    const one = new URL(first.authorizationUrl);
    const two = new URL(second.authorizationUrl);
    expect(first.secret).not.toBe(second.secret);
    expect(one.searchParams.get('state')).not.toBe(two.searchParams.get('state'));
    expect(one.searchParams.get('code_challenge_method')).toBe('S256');
    expect(one.searchParams.get('nonce')).toBeTruthy();
    expect(first.authorizationUrl).not.toContain(first.secret);
    expect(prisma.socialLoginFlow.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          provider: 'google',
          stateHash: expect.any(String),
          pollSecretHash: expect.any(String),
          codeVerifier: expect.any(String),
        }),
      }),
    );
    const stored = prisma.socialLoginFlow.create.mock.calls[0][0].data;
    expect(stored.stateHash).toBe(
      createHash('sha256').update(one.searchParams.get('state')!).digest('hex'),
    );
  });

  it('never sends an encrypted session to anyone with the wrong pairing secret', async () => {
    prisma.socialLoginFlow.findUnique.mockResolvedValue({
      id: 'd1a7fd75-83f5-4e52-917d-082b25643bb9',
      pollSecretHash: createHash('sha256').update('right-secret-xxxxxxxxxxxxxxxxxxxxxxxx').digest('hex'),
      expiresAt: new Date(Date.now() + 100000),
      status: 'completed',
      resultCiphertext: 'encrypted.session.goes.here',
    });
    await expect(social.poll('d1a7fd75-83f5-4e52-917d-082b25643bb9',
      'wrong-secret-xxxxxxxxxxxxxxxxxxxxxxxx'))
      .rejects.toBeInstanceOf(UnauthorizedException);
    expect(prisma.socialLoginFlow.updateMany).not.toHaveBeenCalled();
  });

  it('consumes one-time encrypted session exactly once', async () => {
    const secret = randomBytes(32).toString('base64url');
    const session = { accessToken: 'access', refreshToken: 'refresh', user: {
      id: 'user-a', email: 'a@example.com',
    }};
    const encrypted = (social as any).encryptResult(session);
    const flow = {
      id: 'd1a7fd75-83f5-4e52-917d-082b25643bb9',
      pollSecretHash: createHash('sha256').update(secret).digest('hex'),
      expiresAt: new Date(Date.now() + 100000),
      status: 'completed', resultCiphertext: encrypted,
    };
    prisma.socialLoginFlow.findUnique.mockResolvedValue(flow);
    prisma.socialLoginFlow.updateMany.mockResolvedValueOnce({ count: 1 });
    const done = await social.poll(flow.id, secret);
    expect(done).toEqual({ status: 'completed', session });
    expect(prisma.socialLoginFlow.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ id: flow.id, status: 'completed' }),
        data: { status: 'consumed', resultCiphertext: null },
      }),
    );
    prisma.socialLoginFlow.updateMany.mockResolvedValueOnce({ count: 0 });
    await expect(social.poll(flow.id, secret))
      .rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('verifies the OIDC JWT signature and nonce with the provider JWKS', async () => {
    const pair = generateKeyPairSync('rsa', { modulusLength: 2048 });
    const jwk = pair.publicKey.export({ format: 'jwk' }) as any;
    jwk.kid = 'test-key';
    jwk.alg = 'RS256';
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ keys: [jwk] }),
    } as unknown as Response);
    const nonce = 'test-challenge';
    const token = (subject: string, challenge: string) => {
      const header = Buffer.from(JSON.stringify({
        typ: 'JWT', alg: 'RS256', kid: 'test-key',
      })).toString('base64url');
      const payload = Buffer.from(JSON.stringify({
        iss: 'https://accounts.google.com',
        aud: config.GOOGLE_OAUTH_CLIENT_ID,
        exp: Math.floor(Date.now() / 1000) + 300,
        iat: Math.floor(Date.now() / 1000),
        sub: subject,
        nonce: challenge,
        email: 'signed@example.com',
        email_verified: true,
      })).toString('base64url');
      const message = header + '.' + payload;
      const sig = sign('RSA-SHA256', Buffer.from(message), pair.privateKey);
      return message + '.' + sig.toString('base64url');
    };
    const cfg = (social as any).config('google');
    await expect((social as any).verifyIdentity(token('subject', nonce),
      'google', cfg, nonce)).resolves.toMatchObject({
        subject: 'subject', email: 'signed@example.com',
    });
    await expect((social as any).verifyIdentity(token('subject', 'incorrect'),
      'google', cfg, nonce)).rejects.toBeInstanceOf(UnauthorizedException);
    const corrupted = token('subject', nonce).split('.');
    corrupted[2] = Buffer.from('bad-signature').toString('base64url');
    await expect((social as any).verifyIdentity(corrupted.join('.'),
      'google', cfg, nonce)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('requires deliberate linking instead of hijacking a password account by email', async () => {
    prisma.socialAuthIdentity.findUnique.mockResolvedValue(null);
    prisma.user.findFirst.mockResolvedValue({ id: 'existing-password-user' });
    await expect((social as any).findOrCreateUser('google',
      'provider-subject', 'existing@example.com', 'Display Name'))
      .rejects.toBeInstanceOf(ConflictException);
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('rejects reused or expired state before any identity exchange', async () => {
    const state = randomBytes(32).toString('base64url');
    prisma.socialLoginFlow.findUnique.mockResolvedValue({
      id: 'flow', provider: 'google',
      expiresAt: new Date(Date.now() - 1000),
    });
    await expect(social.callback('google', state, 'code'))
      .rejects.toBeInstanceOf(UnauthorizedException);
    expect(global.fetch).toBe(originalFetch);
    expect(prisma.socialLoginFlow.updateMany).not.toHaveBeenCalled();
  });
});
