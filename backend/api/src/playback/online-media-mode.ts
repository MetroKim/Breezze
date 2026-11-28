/**
 * V8 online-only audio mode: provider-hosted tracks are streamed on demand.
 * It does not require a Breezze-owned music collection or R2 audio assets.
 *
 * Explicit environment configuration is required until the mode passes
 * native and live-provider acceptance; existing production behavior is
 * preserved. Metadata, listener playlists and auth data can still be stored.
 */
export const ONLINE_ONLY_MEDIA_MODE = 'online_only';

export function isOnlineOnlyMediaMode(
  env: Pick<NodeJS.ProcessEnv, 'BREEZZE_MEDIA_MODE'> = process.env,
): boolean {
  return env.BREEZZE_MEDIA_MODE?.trim().toLowerCase() === ONLINE_ONLY_MEDIA_MODE;
}
