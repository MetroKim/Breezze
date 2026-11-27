import {
  audioProofEnabled, AudioProofService,
  PUBLIC_AUDIO_PROOF_ID, PUBLIC_AUDIO_PROOF_SOURCE,
} from './audio-proof.service';

describe('AudioProofService – verified public-domain music only', () => {
  const existing = {
    enabled: process.env.BREEZZE_PUBLIC_AUDIO_PROOF,
    node: process.env.NODE_ENV,
    railway: process.env.RAILWAY_ENVIRONMENT_NAME,
  };

  afterEach(() => {
    if (existing.enabled == null) delete process.env.BREEZZE_PUBLIC_AUDIO_PROOF;
    else process.env.BREEZZE_PUBLIC_AUDIO_PROOF = existing.enabled;
    if (existing.node == null) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = existing.node;
    if (existing.railway == null) delete process.env.RAILWAY_ENVIRONMENT_NAME;
    else process.env.RAILWAY_ENVIRONMENT_NAME = existing.railway;
  });

  it('is denied by default, and never allowed in production', () => {
    expect(audioProofEnabled({})).toBe(false);
    expect(audioProofEnabled({BREEZZE_PUBLIC_AUDIO_PROOF:'true', NODE_ENV:'production'})).toBe(false);
    expect(audioProofEnabled({BREEZZE_PUBLIC_AUDIO_PROOF:'true', RAILWAY_ENVIRONMENT_NAME:'production'})).toBe(false);
    expect(audioProofEnabled({BREEZZE_PUBLIC_AUDIO_PROOF:'true', NODE_ENV:'test'})).toBe(true);
  });

  it('returns an original artist track and the exact verified MP3 source in test mode', () => {
    process.env.BREEZZE_PUBLIC_AUDIO_PROOF = 'true';
    process.env.NODE_ENV = 'test';
    delete process.env.RAILWAY_ENVIRONMENT_NAME;
    const service = new AudioProofService();
    const track = service.track();
    const playable = service.playback();
    expect(track).toMatchObject({
      id: PUBLIC_AUDIO_PROOF_ID, title:'Promise', artist:'Keith Adler',
      license:'Public domain (PD-self)', fullTrack:true,
      offlineAllowed:false, experimental:true,
    });
    expect(playable.streamUrl).toBe(PUBLIC_AUDIO_PROOF_SOURCE);
    expect(playable.streamUrl).toMatch(/^https:\/\/upload\.wikimedia\.org\//);
    expect(playable.mimeType).toBe('audio/mpeg');
    expect(new Date(playable.expiresAt).getTime()).toBeGreaterThan(Date.now());
  });

  it('fails closed when flag is missing', () => {
    delete process.env.BREEZZE_PUBLIC_AUDIO_PROOF;
    const service = new AudioProofService();
    expect(() => service.track()).toThrow('AUDIO_PROOF_DISABLED');
  });
});
