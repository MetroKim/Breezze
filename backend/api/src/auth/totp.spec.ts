import {
  decryptTotpSecret,
  encryptTotpSecret,
  generateTotpSecret,
  totpProvisioningUri,
  verifyTotp,
} from './totp';

describe('TOTP primitives', () => {
  beforeEach(() => {
    process.env.MFA_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');
  });

  it('verifies RFC 6238 SHA-1 test vector at 59 seconds', () => {
    expect(verifyTotp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', '287082', 59_000)).toBe(true);
    expect(verifyTotp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', '287083', 59_000)).toBe(false);
  });

  it('rejects malformed codes and secrets', () => {
    expect(verifyTotp('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ', '12345', 59_000)).toBe(false);
    expect(() => verifyTotp('not-valid!', '123456', 59_000)).toThrow('MFA_SECRET_INVALID');
  });

  it('generates base32 secrets and encrypts them with authenticated encryption', () => {
    const secret = generateTotpSecret();
    expect(secret).toMatch(/^[A-Z2-7]+$/);
    const encrypted = encryptTotpSecret(secret);
    expect(encrypted).not.toContain(secret);
    expect(decryptTotpSecret(encrypted)).toBe(secret);
  });

  it('builds a standards-compatible authenticator provisioning URI', () => {
    expect(totpProvisioningUri('ABC234', 'admin@example.com')).toBe(
      'otpauth://totp/Breezze%3Aadmin%40example.com?secret=ABC234&issuer=Breezze&algorithm=SHA1&digits=6&period=30',
    );
  });

  it('rejects an invalid encryption key length', () => {
    process.env.MFA_ENCRYPTION_KEY = Buffer.alloc(16).toString('base64');
    expect(() => encryptTotpSecret('ABC234')).toThrow('MFA_ENCRYPTION_KEY_MUST_BE_32_BYTES_BASE64');
  });
});
