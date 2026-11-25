import { ForbiddenException } from '@nestjs/common';
import { assertLegacyAuthAllowed, jwtSecretForEnvironment } from './legacy-auth-policy';
import { AuthController } from './auth.controller';
import type { AuthService } from './auth.service';
import type { SupabaseExchangeService } from './supabase-exchange.service';

describe('Production Supabase-only identity boundaries', () => {
  it('rejects new legacy login and registration in production', () => {
    expect(() => assertLegacyAuthAllowed('production')).toThrow(ForbiddenException);
    expect(() => assertLegacyAuthAllowed('production')).toThrow('SUPABASE_AUTH_REQUIRED');
    expect(() => assertLegacyAuthAllowed('test')).not.toThrow();
  });

  it('enforces the legacy login guard before touching account storage', () => {
    const auth = { register: jest.fn(), login: jest.fn() };
    const controller = new AuthController(
      auth as unknown as AuthService,
      {} as SupabaseExchangeService,
    );
    const oldEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';
    try {
      expect(() => controller.login({
        email: 'breezze-user@example.invalid',
        password: 'irrelevant',
      })).toThrow('SUPABASE_AUTH_REQUIRED');
      expect(() => controller.register({
        email: 'breezze-user@example.invalid',
        password: 'secure-secret-123',
      })).toThrow('SUPABASE_AUTH_REQUIRED');
      expect(auth.login).not.toHaveBeenCalled();
      expect(auth.register).not.toHaveBeenCalled();
    } finally {
      if (oldEnv === undefined) delete process.env.NODE_ENV;
      else process.env.NODE_ENV = oldEnv;
    }
  });

  it('refuses a missing, blank or too-short JWT secret in production', () => {
    for (const value of [undefined, '', 'short', '  ']) {
      expect(() => jwtSecretForEnvironment('production', value))
        .toThrow('JWT_SECRET_REQUIRED_PRODUCTION');
    }
  });

  it('permits an adequately configured production JWT secret', () => {
    const valid = 'L'.repeat(48);
    expect(jwtSecretForEnvironment('production', valid)).toBe(valid);
    expect(jwtSecretForEnvironment('test', undefined)).toBe(
      'dev-only-secret-change-me',
    );
  });
});
