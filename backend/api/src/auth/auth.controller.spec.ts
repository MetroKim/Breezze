import { validateSync } from 'class-validator';
import { MfaRecoveryRegenerationDto, SupabaseLinkLegacyDto } from './auth.controller';

describe('MfaRecoveryRegenerationDto', () => {
  const validDto = (code: string) =>
    Object.assign(new MfaRecoveryRegenerationDto(), {
      password: 'correct horse battery staple',
      code,
    });

  it('accepts a six-digit TOTP code', () => {
    expect(validateSync(validDto('123456'))).toHaveLength(0);
  });

  it('accepts a formatted recovery code', () => {
    expect(validateSync(validDto('A1B2-C3D4-E5F6-7890'))).toHaveLength(0);
  });

  it('rejects malformed MFA codes', () => {
    expect(validateSync(validDto('12AB56')).some((error) => error.property === 'code')).toBe(true);
  });

  it('requires a password for recovery-code regeneration', () => {
    const dto = Object.assign(new MfaRecoveryRegenerationDto(), { code: '123456' });
    expect(validateSync(dto).some((error) => error.property === 'password')).toBe(true);
  });
});

describe('SupabaseLinkLegacyDto', () => {
  const validDto = () => Object.assign(new SupabaseLinkLegacyDto(), {
    accessToken: 'a'.repeat(100),
    legacyEmail: 'old@example.com',
    legacyPassword: 'previous-account-password',
  });

  it('requires a verified token and the old account credentials', () => {
    expect(validateSync(validDto())).toHaveLength(0);
    const missing = Object.assign(new SupabaseLinkLegacyDto(), {
      accessToken: 'a'.repeat(100),
    });
    expect(validateSync(missing).map((e) => e.property))
      .toEqual(expect.arrayContaining(['legacyEmail', 'legacyPassword']));
  });

  it('rejects excessively long passwords and malformed legacy email', () => {
    const invalid = validDto();
    invalid.legacyEmail = 'invalid-email';
    invalid.legacyPassword = 'a'.repeat(129);
    const fields = validateSync(invalid).map((e) => e.property);
    expect(fields).toContain('legacyEmail');
    expect(fields).toContain('legacyPassword');
  });
});
