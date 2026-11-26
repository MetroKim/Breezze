import { BadRequestException } from '@nestjs/common';

/**
 * Decode an explicitly user-selected, bounded PNG thumbnail. Never accept
 * external URLs, provider artwork downloads, SVG scripts, arbitrary binaries,
 * or data-URI prefixes. Return only normalized base64 for private persistence.
 */
export function validatePngThumbnail(input: string | null): string | null {
  if (input === null) return null;
  if (
    typeof input !== 'string' || input.length === 0 ||
    input.length > 350000 || input.length % 4 !== 0 ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(input)
  ) {
    throw new BadRequestException('IMAGE_INVALID_ENCODING');
  }

  const bytes = Buffer.from(input, 'base64');
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (
    bytes.length < 45 || bytes.length > 256000 ||
    !bytes.subarray(0, 8).equals(signature) ||
    bytes.toString('ascii', 12, 16) !== 'IHDR'
  ) {
    throw new BadRequestException('IMAGE_INVALID_PNG');
  }

  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  if (width < 1 || height < 1 || width > 512 || height > 512) {
    throw new BadRequestException('IMAGE_INVALID_DIMENSIONS');
  }

  return bytes.toString('base64');
}
