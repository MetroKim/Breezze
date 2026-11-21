import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from 'node:crypto';

const STEP_SECONDS = 30;
const DIGITS = 6;
const WINDOW = 1;

function encryptionKey(): Buffer {
  const encoded = process.env.MFA_ENCRYPTION_KEY;
  if (!encoded) throw new Error('MFA_ENCRYPTION_KEY_REQUIRED');
  const key = Buffer.from(encoded, 'base64');
  if (key.length !== 32) throw new Error('MFA_ENCRYPTION_KEY_MUST_BE_32_BYTES_BASE64');
  return key;
}

export function encryptTotpSecret(secret: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(secret, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [iv, tag, ciphertext].map((part) => part.toString('base64url')).join('.');
}

export function decryptTotpSecret(encrypted: string): string {
  const [ivPart, tagPart, ciphertextPart] = encrypted.split('.');
  if (!ivPart || !tagPart || !ciphertextPart) throw new Error('MFA_SECRET_INVALID');
  const decipher = createDecipheriv(
    'aes-256-gcm',
    encryptionKey(),
    Buffer.from(ivPart, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tagPart, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextPart, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

function codeForCounter(secret: string, counter: number): string {
  const key = Buffer.from(secret, 'base32');
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac('sha1', key).update(message).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const binary = digest.readUInt32BE(offset) & 0x7fffffff;
  return String(binary % 10 ** DIGITS).padStart(DIGITS, '0');
}

export function generateTotpSecret(): string {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const bytes = randomBytes(20);
  let bits = 0;
  let value = 0;
  let output = '';
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      output += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) output += alphabet[(value << (5 - bits)) & 31];
  return output;
}

export function verifyTotp(secret: string, candidate: string, now = Date.now()): boolean {
  if (!/^\d{6}$/.test(candidate)) return false;
  const counter = Math.floor(now / 1000 / STEP_SECONDS);
  const supplied = Buffer.from(candidate);
  for (let offset = -WINDOW; offset <= WINDOW; offset += 1) {
    const expected = Buffer.from(codeForCounter(secret, counter + offset));
    if (expected.length === supplied.length && timingSafeEqual(expected, supplied)) return true;
  }
  return false;
}

export function totpProvisioningUri(secret: string, email: string): string {
  const label = encodeURIComponent(`Breezze:${email}`);
  const issuer = encodeURIComponent('Breezze');
  return `otpauth://totp/${label}?secret=${secret}&issuer=${issuer}&algorithm=SHA1&digits=6&period=${STEP_SECONDS}`;
}
