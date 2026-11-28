/**
 * V8 target encoding ladder for verified, rights-cleared local masters.
 *
 * This is an additive, non-deployed transcode *contract*: no credentials,
 * source URLs, R2 writes, playback grants or FFmpeg subprocesses here.
 * The four legacy R2 variant keys remain authoritative until the Worker,
 * Prisma, native decoder and offline contracts are migrated together.
 *
 * Important: HLS Opus support differs across six target OSes. No Opus tier
 * can be advertised as generally available until native and web acceptance.
 */
export const V8_AUDIO_PROFILE_IDS = [
  'OPUS_64', 'AAC_128', 'AAC_256', 'OPUS_320', 'LOSSLESS', 'HI_RES',
] as const;

export type V8AudioProfileId = typeof V8_AUDIO_PROFILE_IDS[number];
export type LegacyR2AudioVariant = 'AAC_128' | 'AAC_256' | 'LOSSLESS' | 'HI_RES';

export interface SourceAudioFacts {
  /** The actual decoded source, from a trusted FFprobe/ingestion step. */
  codec: string;
  sampleRateHz: number;
  bitDepth: number | null;
  channels: number;
  /** True only for independently verified lossless original/master audio. */
  sourceIsLossless: boolean;
}

export interface AudioRenditionPlan {
  id: V8AudioProfileId;
  label: string;
  codec: 'opus' | 'aac' | 'flac';
  container: 'ogg' | 'm4a' | 'flac';
  mimeType: string;
  /** Nominal bitrate. FLAC is variable and source-dependent. */
  nominalKbps: number | null;
  /** Existing Worker/R2 path contract, null if migration is still needed. */
  legacyR2Variant: LegacyR2AudioVariant | null;
  /** These are encoder options, not shell commands or an executable plan. */
  encoderArgs: readonly string[];
  /** Output MUST be probed for true codec, sample rate and depth afterwards. */
  maximumSampleRateHz: number;
  maximumBitDepth: number | null;
  /** A codec/platform test is needed even when a matching source exists. */
  requiresPlatformAcceptance: boolean;
}

const ladder = {
  OPUS_64: {
    label: 'Data Saver', codec: 'opus', container: 'ogg',
    mimeType: 'audio/ogg', nominalKbps: 64,
    legacyR2Variant: null, requiresPlatformAcceptance: true,
  },
  AAC_128: {
    label: 'Standard', codec: 'aac', container: 'm4a',
    mimeType: 'audio/mp4', nominalKbps: 128,
    legacyR2Variant: 'AAC_128', requiresPlatformAcceptance: false,
  },
  AAC_256: {
    label: 'High', codec: 'aac', container: 'm4a',
    mimeType: 'audio/mp4', nominalKbps: 256,
    legacyR2Variant: 'AAC_256', requiresPlatformAcceptance: false,
  },
  OPUS_320: {
    label: 'Very High', codec: 'opus', container: 'ogg',
    mimeType: 'audio/ogg', nominalKbps: 320,
    legacyR2Variant: null, requiresPlatformAcceptance: true,
  },
  LOSSLESS: {
    label: 'B-Lossless', codec: 'flac', container: 'flac',
    mimeType: 'audio/flac', nominalKbps: null,
    legacyR2Variant: 'LOSSLESS', requiresPlatformAcceptance: false,
  },
  HI_RES: {
    label: 'Hi-Res', codec: 'flac', container: 'flac',
    mimeType: 'audio/flac', nominalKbps: null,
    legacyR2Variant: 'HI_RES', requiresPlatformAcceptance: true,
  },
} as const satisfies Record<V8AudioProfileId, {
  label: string;
  codec: 'opus' | 'aac' | 'flac';
  container: 'ogg' | 'm4a' | 'flac';
  mimeType: string;
  nominalKbps: number | null;
  legacyR2Variant: LegacyR2AudioVariant | null;
  requiresPlatformAcceptance: boolean;
}>;

function validSourceFacts(input: SourceAudioFacts): boolean {
  return !!input && typeof input.codec === 'string' && input.codec.length > 0 &&
    Number.isSafeInteger(input.sampleRateHz) &&
    input.sampleRateHz >= 8_000 && input.sampleRateHz <= 384_000 &&
    (input.bitDepth === null ||
      (Number.isSafeInteger(input.bitDepth) && input.bitDepth >= 8 && input.bitDepth <= 32)) &&
    Number.isSafeInteger(input.channels) && input.channels >= 1 && input.channels <= 8 &&
    typeof input.sourceIsLossless === 'boolean';
}

/**
 * Return null rather than invent a new media capability.
 * Authorization, correct recording identity and territorial rights must
 * already have been checked independently by the ingestion service.
 */
export function planV8Rendition(
  id: V8AudioProfileId,
  master: SourceAudioFacts,
): AudioRenditionPlan | null {
  if (!Object.prototype.hasOwnProperty.call(ladder, id) ||
      !validSourceFacts(master)) return null;

  const profile = ladder[id];
  const isFlac = profile.codec === 'flac';
  if (isFlac && !master.sourceIsLossless) return null;

  // Hi-Res is reserved for *genuinely* higher-than-CD-quality masters.
  // We must never create a 24/192 label from 16/44.1 or lossy audio.
  if (id === 'HI_RES' &&
      (master.bitDepth === null || master.bitDepth < 24 ||
       master.sampleRateHz <= 48_000)) return null;

  const sampleRateHz = isFlac
    ? Math.min(master.sampleRateHz, 192_000)
    : Math.min(master.sampleRateHz, 48_000);
  const maxBitDepth = master.bitDepth === null
    ? null : Math.min(master.bitDepth, 24);

  const encoderArgs: string[] =
    profile.codec === 'opus'
      ? ['-vn', '-map', '0:a:0', '-c:a', 'libopus',
         '-b:a', String(profile.nominalKbps) + 'k',
         '-vbr', 'on', '-ar', String(sampleRateHz)]
    : profile.codec === 'aac'
      ? ['-vn', '-map', '0:a:0', '-c:a', 'aac',
         '-b:a', String(profile.nominalKbps) + 'k',
         '-ar', String(sampleRateHz), '-movflags', '+faststart']
    : ['-vn', '-map', '0:a:0', '-c:a', 'flac',
       '-compression_level', '8', '-ar', String(sampleRateHz)];

  return {
    id, label: profile.label, codec: profile.codec,
    container: profile.container, mimeType: profile.mimeType,
    nominalKbps: profile.nominalKbps,
    legacyR2Variant: profile.legacyR2Variant,
    encoderArgs, maximumSampleRateHz: sampleRateHz,
    maximumBitDepth: maxBitDepth,
    requiresPlatformAcceptance: profile.requiresPlatformAcceptance,
  };
}

export function planV8EncodingLadder(master: SourceAudioFacts): AudioRenditionPlan[] {
  return V8_AUDIO_PROFILE_IDS
    .map(id => planV8Rendition(id, master))
    .filter((plan): plan is AudioRenditionPlan => plan !== null);
}

/** Only old compatible variants may currently be registered in Prisma/R2. */
export function isReadyForLegacyMediaStorage(plan: AudioRenditionPlan): boolean {
  return plan.legacyR2Variant !== null;
}
