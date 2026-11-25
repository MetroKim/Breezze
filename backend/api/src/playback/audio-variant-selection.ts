export const AUDIO_QUALITY_ORDER = ['AAC_128', 'AAC_256', 'LOSSLESS', 'HI_RES'] as const;
export type AudioQuality = typeof AUDIO_QUALITY_ORDER[number];

export interface ReadyAudioVariant {
  quality: string;
  mimeType: string;
  sizeBytes: bigint;
}

/**
 * Pick a verified, existing encoding without exceeding the requested quality
 * or the maximum authorized by the rights decision. No phantom R2 URLs.
 */
export function selectReadyAudioVariant(
  assets: ReadonlyArray<ReadyAudioVariant>,
  requested: string,
  rightsCeiling: string | null,
): ReadyAudioVariant | null {
  const requestedIndex = AUDIO_QUALITY_ORDER.indexOf(requested as AudioQuality);
  const rightsIndex = rightsCeiling == null
    ? AUDIO_QUALITY_ORDER.length - 1
    : AUDIO_QUALITY_ORDER.indexOf(rightsCeiling as AudioQuality);
  if (requestedIndex < 0 || rightsIndex < 0) return null;

  const ceiling = Math.min(requestedIndex, rightsIndex);
  const eligible = new Map<string, ReadyAudioVariant>();
  for (const asset of assets) {
    if (asset.sizeBytes <= 0n) continue;
    const allowedMime = asset.quality === 'LOSSLESS' || asset.quality === 'HI_RES'
      ? ['audio/flac', 'audio/x-flac']
      : ['audio/mp4', 'audio/aac'];
    if (!allowedMime.includes(asset.mimeType.toLowerCase())) continue;
    eligible.set(asset.quality, asset);
  }
  for (let index = ceiling; index >= 0; index--) {
    const asset = eligible.get(AUDIO_QUALITY_ORDER[index]);
    if (asset) return asset;
  }
  return null;
}
