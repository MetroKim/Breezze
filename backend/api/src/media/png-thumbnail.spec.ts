import { BadRequestException } from '@nestjs/common';
import { validatePngThumbnail } from './png-thumbnail';

const valid = (
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC' +
  'AAAAC0lEQVR42mP8/x8AAwMCAO+/+5AAAAAASUVORK5CYII='
);

describe('private PNG thumbnail validator', () => {
  it('accepts and normalizes a bounded valid PNG', () => {
    expect(validatePngThumbnail(valid)).toBe(valid);
    expect(validatePngThumbnail(null)).toBeNull();
  });
  it('rejects external URLs, SVG, invalid base64 and oversized images', () => {
    for (const invalid of [
      'https://example.com/cover.png',
      'data:image/png;base64,' + valid,
      Buffer.from('<svg onload="alert(1)"/>').toString('base64'),
      'A'.repeat(350004),
    ]) {
      expect(() => validatePngThumbnail(invalid)).toThrow(BadRequestException);
    }
  });
  it('rejects PNGs whose dimensions are outside safe bounds', () => {
    const bytes = Buffer.from(valid, 'base64');
    bytes.writeUInt32BE(4096, 16);
    expect(() => validatePngThumbnail(bytes.toString('base64')))
      .toThrow('IMAGE_INVALID_DIMENSIONS');
  });
});
