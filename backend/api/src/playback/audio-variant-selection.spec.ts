import { selectReadyAudioVariant } from './audio-variant-selection';

const audio = (quality: string, sizeBytes = 999n) => ({
  quality, sizeBytes,
  mimeType: quality.includes('LOSSLESS') || quality === 'HI_RES' ? 'audio/flac' : 'audio/mp4',
});

describe('audio asset registry selection', () => {
  it('uses available best quality within rights ceiling', () => {
    expect(selectReadyAudioVariant(
      [audio('AAC_128'), audio('LOSSLESS')], 'HI_RES', null,
    )?.quality).toBe('LOSSLESS');
    expect(selectReadyAudioVariant(
      [audio('AAC_128'), audio('LOSSLESS')], 'HI_RES', 'AAC_128',
    )?.quality).toBe('AAC_128');
  });

  it('rejects missing, empty, mismatched-codec and invalid asset variants', () => {
    expect(selectReadyAudioVariant([], 'AAC_256', null)).toBeNull();
    expect(selectReadyAudioVariant([audio('LOSSLESS')], 'AAC_256', null)).toBeNull();
    expect(selectReadyAudioVariant([audio('AAC_128', 0n)], 'AAC_128', null)).toBeNull();
    expect(selectReadyAudioVariant(
      [{ ...audio('AAC_256'), mimeType: 'video/mp4' }], 'AAC_256', null,
    )).toBeNull();
    expect(selectReadyAudioVariant([audio('AAC_128')], 'UNKNOWN', null)).toBeNull();
    expect(selectReadyAudioVariant([audio('AAC_128')], 'AAC_256', 'UNKNOWN')).toBeNull();
  });
});
