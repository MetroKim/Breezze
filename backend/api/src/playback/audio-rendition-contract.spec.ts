import {
  planV8EncodingLadder, planV8Rendition, isReadyForLegacyMediaStorage,
  V8_AUDIO_PROFILE_IDS, SourceAudioFacts,
} from './audio-rendition-contract';

const studioMaster: SourceAudioFacts = {
  codec: 'flac', sampleRateHz: 96_000,
  bitDepth: 24, channels: 2, sourceIsLossless: true,
};

describe('V8 full-audio rendition encoding contract', () => {
  it('defines all six distinct target codecs/bitrates without claiming they are deployed', () => {
    expect(V8_AUDIO_PROFILE_IDS).toEqual([
      'OPUS_64', 'AAC_128', 'AAC_256', 'OPUS_320', 'LOSSLESS', 'HI_RES',
    ]);
    const ladder = planV8EncodingLadder(studioMaster);
    expect(ladder.map(r => [r.id, r.mimeType, r.nominalKbps])).toEqual([
      ['OPUS_64', 'audio/ogg', 64],
      ['AAC_128', 'audio/mp4', 128],
      ['AAC_256', 'audio/mp4', 256],
      ['OPUS_320', 'audio/ogg', 320],
      ['LOSSLESS', 'audio/flac', null],
      ['HI_RES', 'audio/flac', null],
    ]);
    expect(ladder.filter(isReadyForLegacyMediaStorage).map(r => r.id))
      .toEqual(['AAC_128', 'AAC_256', 'LOSSLESS', 'HI_RES']);
    expect(ladder.filter(r => r.legacyR2Variant === null).map(r => r.id))
      .toEqual(['OPUS_64', 'OPUS_320']);
    expect(ladder.filter(r => r.requiresPlatformAcceptance).map(r => r.id))
      .toEqual(['OPUS_64', 'OPUS_320', 'HI_RES']);
  });

  it('never generates true FLAC/lossless tiers from a lossy source', () => {
    const mp3: SourceAudioFacts = {
      codec: 'mp3', sampleRateHz: 44_100,
      bitDepth: null, channels: 2, sourceIsLossless: false,
    };
    expect(planV8Rendition('LOSSLESS', mp3)).toBeNull();
    expect(planV8Rendition('HI_RES', mp3)).toBeNull();
    expect(planV8EncodingLadder(mp3).map(r => r.id))
      .toEqual(['OPUS_64', 'AAC_128', 'AAC_256', 'OPUS_320']);
  });

  it('does not mislabel 16-bit CD-quality PCM as genuine Hi-Res', () => {
    const cd: SourceAudioFacts = {
      codec: 'pcm_s16le', sampleRateHz: 44_100,
      bitDepth: 16, channels: 2, sourceIsLossless: true,
    };
    expect(planV8Rendition('LOSSLESS', cd)?.maximumSampleRateHz).toBe(44_100);
    expect(planV8Rendition('HI_RES', cd)).toBeNull();
    expect(planV8Rendition('LOSSLESS', cd)?.maximumBitDepth).toBe(16);
    expect(planV8Rendition('OPUS_320', cd)?.encoderArgs)
      .toContain('48_000'.replace('_', ''));
  });

  it('caps requested output sampling at source/24-bit 192 kHz, not a fake upscale', () => {
    const master: SourceAudioFacts = { ...studioMaster, sampleRateHz: 384_000, bitDepth: 32 };
    const h = planV8Rendition('HI_RES', master);
    expect(h).not.toBeNull();
    expect(h?.maximumSampleRateHz).toBe(192_000);
    expect(h?.maximumBitDepth).toBe(24);
    expect(h?.encoderArgs).toEqual([
      '-vn', '-map', '0:a:0', '-c:a', 'flac',
      '-compression_level', '8', '-ar', '192000',
    ]);
  });

  it('contains only whitelisted FFmpeg arguments, no source path or shell interpolation', () => {
    const plan = planV8Rendition('AAC_128', studioMaster);
    expect(plan?.encoderArgs).toEqual([
      '-vn', '-map', '0:a:0', '-c:a', 'aac',
      '-b:a', '128k', '-ar', '48000', '-movflags', '+faststart',
    ]);
    expect(plan?.encoderArgs.join(' ')).not.toMatch(/https?:|\.\.|;|\$\(/);
  });

  it('rejects unsupported profiles and impossible/unverified input facts', () => {
    expect(planV8Rendition('AAC_999' as never, studioMaster)).toBeNull();
    for (const invalid of [
      { ...studioMaster, sampleRateHz: 0 },
      { ...studioMaster, sampleRateHz: Number.NaN },
      { ...studioMaster, channels: 0 },
      { ...studioMaster, bitDepth: -16 },
      { ...studioMaster, sourceIsLossless: undefined },
    ]) {
      expect(planV8EncodingLadder(invalid as SourceAudioFacts)).toEqual([]);
    }
  });
});
