import {
  ConflictException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { SupabaseExchangeService } from './supabase-exchange.service';
import { PrismaService } from '../prisma.service';

describe('SupabaseExchangeService', () => {
  const token =
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJleGFtcGxlIn0.c2lnbmF0dXJl';
  const supabaseUser = {
    id: '1d4ea108-a765-4c0a-bca0-f9f32b661204',
    email: 'listener@example.com',
    email_confirmed_at: '2026-11-24T00:00:00Z',
  };
  const savedUrl = process.env.SUPABASE_URL;
  const savedKey = process.env.SUPABASE_PUBLISHABLE_KEY;
  let service: SupabaseExchangeService;
  let prisma: any;
  let auth: any;

  beforeEach(() => {
    process.env.SUPABASE_URL = 'https://breezze-test.supabase.co';
    process.env.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_test';
    prisma = {
      socialAuthIdentity: {
        findUnique: jest.fn().mockResolvedValue(null),
      },
      user: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'breezze-user-id' }),
      },
    };
    auth = {
      issueVerifiedSocialSession: jest.fn().mockResolvedValue({
        accessToken: 'breezze-access',
        refreshToken: 'breezze-refresh',
        user: { id: 'breezze-user-id' },
      }),
    };
    service = new SupabaseExchangeService(
      prisma as PrismaService,
      auth as AuthService,
    );
    jest.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify(supabaseUser), { status: 200 }),
    );
  });

  afterEach(() => {
    jest.restoreAllMocks();
    if (savedUrl === undefined) delete process.env.SUPABASE_URL;
    else process.env.SUPABASE_URL = savedUrl;
    if (savedKey === undefined) delete process.env.SUPABASE_PUBLISHABLE_KEY;
    else process.env.SUPABASE_PUBLISHABLE_KEY = savedKey;
  });

  it('exchanges an independently verified identity into a Breezze session', async () => {
    const result = await service.exchange(token);
    expect(result.accessToken).toBe('breezze-access');
    expect(prisma.user.create).toHaveBeenCalledWith({
      data: {
        email: supabaseUser.email,
        passwordHash: expect.any(String),
        socialIdentities: {
          create: {
            provider: 'supabase',
            subject: 'breezze-test.supabase.co:' + supabaseUser.id,
          },
        },
      },
      select: { id: true },
    });
    expect(auth.issueVerifiedSocialSession).toHaveBeenCalledWith(
      'breezze-user-id',
    );
    const [url, init] = (globalThis.fetch as jest.Mock).mock.calls[0];
    expect(String(url)).toContain('/auth/v1/user');
    expect(init.headers.Authorization).toBe(`Bearer ${token}`);
  });

  it('reuses identity mapping without relying on a mutable email', async () => {
    prisma.socialAuthIdentity.findUnique.mockResolvedValue({
      userId: 'existing-breezze-user',
    });
    await service.exchange(token);
    expect(prisma.user.findFirst).not.toHaveBeenCalled();
    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(auth.issueVerifiedSocialSession).toHaveBeenCalledWith(
      'existing-breezze-user',
    );
  });

  it('rejects unverified email before database access', async () => {
    (globalThis.fetch as jest.Mock).mockResolvedValue(
      new Response(
        JSON.stringify({ ...supabaseUser, email_confirmed_at: null }),
        { status: 200 },
      ),
    );
    await expect(service.exchange(token)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('rejects a token Supabase refuses', async () => {
    (globalThis.fetch as jest.Mock).mockResolvedValue(
      new Response('{}', { status: 401 }),
    );
    await expect(service.exchange(token)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('rejects malformed tokens without any network request', async () => {
    await expect(service.exchange('not-a-token')).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  it('does not silently link a legacy account sharing the email', async () => {
    prisma.user.findFirst.mockResolvedValue({ id: 'legacy-user' });
    await expect(service.exchange(token)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(auth.issueVerifiedSocialSession).not.toHaveBeenCalled();
  });

  it('reuses identity after a concurrent insertion', async () => {
    prisma.user.create.mockRejectedValue({ code: 'P2002' });
    prisma.socialAuthIdentity.findUnique
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ userId: 'winner-user' });
    await service.exchange(token);
    expect(auth.issueVerifiedSocialSession).toHaveBeenCalledWith('winner-user');
  });

  it('fails closed if the Supabase project is not configured', async () => {
    delete process.env.SUPABASE_URL;
    await expect(service.exchange(token)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  it('rejects an insecure or unsupported auth origin', async () => {
    process.env.SUPABASE_URL = 'http://example.invalid';
    await expect(service.exchange(token)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(globalThis.fetch).not.toHaveBeenCalled();
  });

  it('fails closed on Supabase network failure', async () => {
    (globalThis.fetch as jest.Mock).mockRejectedValue(new Error('offline'));
    await expect(service.exchange(token)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
    expect(auth.issueVerifiedSocialSession).not.toHaveBeenCalled();
  });

  it('rejects anonymous identities', async () => {
    (globalThis.fetch as jest.Mock).mockResolvedValue(
      new Response(JSON.stringify({ ...supabaseUser, is_anonymous: true }), {
        status: 200,
      }),
    );
    await expect(service.exchange(token)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
