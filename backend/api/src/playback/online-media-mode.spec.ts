import { isOnlineOnlyMediaMode } from './online-media-mode';

describe('V8 online-only playback mode', () => {
  it('is explicitly enabled, with a case-insensitive trimmed value', () => {
    expect(isOnlineOnlyMediaMode({ BREEZZE_MEDIA_MODE: 'online_only' })).toBe(true);
    expect(isOnlineOnlyMediaMode({ BREEZZE_MEDIA_MODE: ' ONLINE_ONLY ' })).toBe(true);
  });

  it('does not accidentally disable legacy hosted playback', () => {
    expect(isOnlineOnlyMediaMode({})).toBe(false);
    expect(isOnlineOnlyMediaMode({ BREEZZE_MEDIA_MODE: 'hybrid' })).toBe(false);
    expect(isOnlineOnlyMediaMode({ BREEZZE_MEDIA_MODE: 'online' })).toBe(false);
  });
});
