import {
  ConflictException,
  ForbiddenException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import * as argon2 from 'argon2';
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
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'identity-id' }),
      },
      user: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'breezze-user-id' }),
      },
    };
    prisma.$transaction = jest.fn(async (callback: (tx: any) => Promise<unknown>) =>
      callback(prisma));
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
      'breezze-user-id', { supabaseVerified: true },
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
      'existing-breezze-user', { supabaseVerified: true },
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
    expect(auth.issueVerifiedSocialSession).toHaveBeenCalledWith('winner-user', { supabaseVerified: true });
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

  describe('explicit legacy account linking', () => {
    const oldEmail = 'old-listener@example.com';
    const oldPassword = 'long-legacy-secret';

    async function legacyAccount() {
      const passwordHash = await argon2.hash(oldPassword);
      prisma.user.findFirst.mockResolvedValue({
        id: 'legacy-account-id',
        passwordHash,
        role: 'user',
        mfaEnabled: false,
      });
      return passwordHash;
    }

    it('preserves the old user ID after proving both identities', async () => {
      await legacyAccount();
      const result = await service.linkLegacy(token, oldEmail, oldPassword);
      expect(result.accessToken).toBe('breezze-access');
      expect(prisma.user.findFirst).toHaveBeenCalledWith({
        where: { email: { equals: oldEmail, mode: 'insensitive' } },
        select: { id: true, passwordHash: true, role: true, mfaEnabled: true },
      });
      expect(prisma.socialAuthIdentity.create).toHaveBeenCalledWith({
        data: {
          userId: 'legacy-account-id',
          provider: 'supabase',
          subject: 'breezze-test.supabase.co:' + supabaseUser.id,
        },
      });
      expect(prisma.user.create).not.toHaveBeenCalled();
      expect(auth.issueVerifiedSocialSession).toHaveBeenCalledWith('legacy-account-id', { supabaseVerified: true });
      expect(prisma.$transaction).toHaveBeenCalledWith(
        expect.any(Function),
        { isolationLevel: 'Serializable' },
      );
    });

    it('denies an incorrect old password without writing identities', async () => {
      await legacyAccount();
      await expect(service.linkLegacy(token, oldEmail, 'wrong-old-password'))
        .rejects.toBeInstanceOf(UnauthorizedException);
      expect(prisma.$transaction).not.toHaveBeenCalled();
      expect(auth.issueVerifiedSocialSession).not.toHaveBeenCalled();
    });

    it('does not identify whether a legacy email exists', async () => {
      await expect(service.linkLegacy(token, oldEmail, oldPassword))
        .rejects.toThrow('LEGACY_CREDENTIALS_INVALID');
      expect(prisma.socialAuthIdentity.create).not.toHaveBeenCalled();
    });

    it('requires Supabase verification before password checking', async () => {
      (globalThis.fetch as jest.Mock).mockResolvedValue(
        new Response('{}', { status: 401 }),
      );
      await expect(service.linkLegacy(token, oldEmail, oldPassword))
        .rejects.toBeInstanceOf(UnauthorizedException);
      expect(prisma.user.findFirst).not.toHaveBeenCalled();
    });

    it('rejects privileged accounts even with their correct password', async () => {
      const passwordHash = await legacyAccount();
      prisma.user.findFirst.mockResolvedValue({
        id: 'admin-user',
        passwordHash,
        role: 'admin',
        mfaEnabled: true,
      });
      await expect(service.linkLegacy(token, oldEmail, oldPassword))
        .rejects.toBeInstanceOf(ForbiddenException);
      expect(prisma.$transaction).not.toHaveBeenCalled();
    });

    it('rejects linking a Supabase identity already mapped to someone else', async () => {
      await legacyAccount();
      prisma.socialAuthIdentity.findUnique.mockResolvedValue({
        userId: 'other-account-id',
      });
      await expect(service.linkLegacy(token, oldEmail, oldPassword))
        .rejects.toThrow('SUPABASE_IDENTITY_ALREADY_LINKED');
      expect(prisma.socialAuthIdentity.create).not.toHaveBeenCalled();
      expect(auth.issueVerifiedSocialSession).not.toHaveBeenCalled();
    });

    it('rejects a second Supabase subject for the same old account', async () => {
      await legacyAccount();
      prisma.socialAuthIdentity.findFirst.mockResolvedValue({
        subject: 'breezze-test.supabase.co:another-subject',
      });
      await expect(service.linkLegacy(token, oldEmail, oldPassword))
        .rejects.toThrow('LEGACY_ALREADY_LINKED');
      expect(prisma.socialAuthIdentity.create).not.toHaveBeenCalled();
    });

    it('returns the same existing link idempotently', async () => {
      await legacyAccount();
      prisma.socialAuthIdentity.findUnique.mockResolvedValue({
        userId: 'legacy-account-id',
      });
      prisma.socialAuthIdentity.findFirst.mockResolvedValue({
        subject: 'breezze-test.supabase.co:' + supabaseUser.id,
      });
      await service.linkLegacy(token, oldEmail, oldPassword);
      expect(prisma.socialAuthIdentity.create).not.toHaveBeenCalled();
      expect(auth.issueVerifiedSocialSession).toHaveBeenCalledWith('legacy-account-id', { supabaseVerified: true });
    });

    it('returns a conflict rather than claiming an identity on a race', async () => {
      await legacyAccount();
      prisma.socialAuthIdentity.create.mockRejectedValue({ code: 'P2002' });
      await expect(service.linkLegacy(token, oldEmail, oldPassword))
        .rejects.toThrow('LEGACY_LINK_CONFLICT');
      expect(auth.issueVerifiedSocialSession).not.toHaveBeenCalled();
    });
  });
});
