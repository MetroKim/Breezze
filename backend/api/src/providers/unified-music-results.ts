import { ProviderTrack } from './provider-adapter.interface';
import { ProviderResult } from './provider-result';

/**
 * Discovery-only identity grouping for a single Breezze search result list.
 * The representative always retains its OWN provider ID and metadata; never
 * replace a Spotify media/track URL with one from Deezer (or vice versa).
 *
 * A match is NOT a playback authorization, licensing decision, or a grant to
 * redistribute a recording. Provider-specific attribution obligations remain.
 */
export interface MusicSearchShelf {
  providerId: string;
  displayName: string;
  result: ProviderResult<ProviderTrack[]>;
}

export interface UnifiedMusicTrack extends ProviderTrack {
  providerId: string;
  /** Catalog identity hints only. These are never usable media URLs. */
  alternateCatalogIds: Array<{ providerId: string; providerTrackId: string }>;
}

const normalize = (input: string) =>
  input.normalize('NFKC').toLocaleLowerCase('en')
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim().replace(/\s+/g, ' ');

const normalizedIsrc = (isrc?: string) => {
  const value = isrc?.replace(/[-\s]/g, '').toUpperCase() ?? '';
  return /^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$/.test(value) ? value : null;
};

function sameRecording(a: ProviderTrack, b: ProviderTrack): boolean {
  const aIsrc = normalizedIsrc(a.isrc);
  const bIsrc = normalizedIsrc(b.isrc);
  // Two explicit, conflicting recording identifiers must never merge.
  if (aIsrc && bIsrc) return aIsrc === bIsrc;

  if (!a.title.trim() || !a.artist.trim() ||
      !b.title.trim() || !b.artist.trim()) return false;
  if (normalize(a.title) !== normalize(b.title) ||
      normalize(a.artist) !== normalize(b.artist)) return false;

  // Without an ISRC we require duration evidence. A remix, edit or cover
  // must not collapse merely because its display name looks similar.
  const da = a.durationSec;
  const db = b.durationSec;
  return typeof da === 'number' && da > 0 &&
    typeof db === 'number' && db > 0 &&
    Math.abs(da - db) <= 3;
}

/**
 * Spotify-first ordering, Deezer for missing songs, independent backup only
 * when explicitly supplied. No inter-provider media mixing or source spoofing.
 * The API keeps the original provider shelves for provenance/attribution.
 */
export function unifiedMusicResults(
  shelves: readonly MusicSearchShelf[],
): UnifiedMusicTrack[] {
  const results: UnifiedMusicTrack[] = [];
  for (const providerId of ['spotify', 'deezer', 'musicbrainz']) {
    for (const shelf of shelves) {
      if (shelf.providerId !== providerId || shelf.result.kind !== 'ok') continue;
      for (const track of shelf.result.value) {
        if (typeof track.providerTrackId !== 'string' ||
            !track.providerTrackId.trim() ||
            typeof track.title !== 'string' || !track.title.trim() ||
            typeof track.artist !== 'string' || !track.artist.trim()) continue;

        const identicalId = results.find(candidate =>
          candidate.providerId === providerId &&
          candidate.providerTrackId === track.providerTrackId);
        if (identicalId) continue;

        const match = results.find(candidate => sameRecording(candidate, track));
        if (match) {
          if (match.providerId !== providerId &&
              !match.alternateCatalogIds.some(alt =>
                alt.providerId === providerId &&
                alt.providerTrackId === track.providerTrackId)) {
            match.alternateCatalogIds.push({
              providerId, providerTrackId: track.providerTrackId,
            });
          }
          continue;
        }
        results.push({
          ...track,
          providerId,
          alternateCatalogIds: [],
        });
      }
    }
  }
  return results;
}
