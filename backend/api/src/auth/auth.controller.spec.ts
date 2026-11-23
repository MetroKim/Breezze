import { validateSync } from 'class-validator';
import { MfaRecoveryRegenerationDto } from './auth.controller';

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
