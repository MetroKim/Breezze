import { Injectable } from '@nestjs/common';
import {
  ProviderAdapter, ProviderCapabilities, ProviderPlaybackRequest,
  ProviderPlaybackSource, ProviderTrack,
} from './provider-adapter.interface';
import { ProviderCacheService } from './provider-cache.service';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

interface DeezerTrack {
  id?: number;
  title?: string;
  duration?: number;
  link?: string;
  preview?: string;
  isrc?: string;
  artist?: { name?: string };
  album?: { cover_medium?: string; cover_big?: string };
}
interface DeezerEnvelope<T> { data?: T[]; error?: { message?: string }; }
interface DeezerArtistRecord {
  id?: number;
  name?: string;
  picture_medium?: string;
  picture_big?: string;
  link?: string;
  nb_fan?: number;
  nb_album?: number;
}
interface DeezerAlbumRecord {
  id?: number;
  title?: string;
  release_date?: string;
  record_type?: string;
  cover_medium?: string;
  cover_big?: string;
  nb_tracks?: number;
  link?: string;
  artist?: { id?: number; name?: string };
}

export interface DeezerArtistSupplement {
  matchedArtistId: string;
  matchedName: string;
  artistExtra: {
    fans?: number;
    albumCount?: number;
    url: string;
  };
  songs: (ProviderTrack & { providerId: 'deezer' })[];
  albums: Array<{
    providerId: 'deezer';
    id: string;
    title: string;
    type: 'album' | 'single';
    releaseDate: string;
    trackCount: number;
    artworkUrl?: string;
    url: string;
  }>;
  relatedArtists: Array<{
    providerId: 'deezer';
    id: string;
    name: string;
    imageUrl?: string;
    url: string;
  }>;
  songStatus: 'ok' | 'unavailable';
  albumStatus: 'ok' | 'unavailable';
  relatedStatus: 'ok' | 'unavailable';
}

const normalizeArtist = (name: string) =>
  name.normalize('NFKC').toLocaleLowerCase('en').trim().replace(/\s+/g, ' ');


@Injectable()
export class DeezerAdapter implements ProviderAdapter {
  readonly providerId = 'deezer';
  readonly displayName = 'Deezer';
  readonly adapterVersion = '1.0.0';
  readonly priority = 110;
  get enabled(): boolean { return process.env.DEEZER_ENABLED !== 'false'; }
  readonly capabilities: ProviderCapabilities = {
    search: true, metadata: true, availability: false, playback: false,
    download: false, albums: true, artists: true, playlists: false,
  };

  private readonly baseUrl = (process.env.DEEZER_API_URL ?? 'https://api.deezer.com').replace(/\/$/, '');
  constructor(private readonly cache: ProviderCacheService) {}

  private url(path: string, params: Record<string, string> = {}): URL {
    const url = new URL(path.replace(/^\//, ''), `${this.baseUrl}/`);
    for (const [key, value] of Object.entries(params)) url.searchParams.set(key, value);
    return url;
  }

  private async request<T>(url: URL): Promise<T> {
    const response = await fetch(url, {
      headers: { accept: 'application/json', 'user-agent': 'Breezze/1.0' },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`DEEZER_HTTP_${response.status}`);
    const payload = await response.json() as T & { error?: { message?: string } };
    if (payload.error) throw new Error('DEEZER_API_REJECTED_REQUEST');
    return payload as T;
  }

  private mapTrack(track: DeezerTrack): ProviderTrack | null {
    if (!track.id || !track.title?.trim() || !track.artist?.name?.trim()) return null;
    return {
      providerTrackId: String(track.id),
      title: track.title.trim(),
      artist: track.artist.name.trim(),
      artworkUrl: track.album?.cover_big ?? track.album?.cover_medium,
      durationSec: typeof track.duration === 'number' && track.duration > 0 ? track.duration : undefined,
      sourceUrl: track.link,
      isrc: track.isrc,
      previewUrl: track.preview && /^https:\/\/[a-z0-9.-]+\.dzcdn\.net\//i.test(track.preview) ? track.preview : undefined,
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    const key = `provider:deezer:search:v2:${encodeURIComponent(q.toLowerCase())}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;
    try {
      const payload = await this.request<DeezerEnvelope<DeezerTrack>>(
        this.url('/search/track', { q, limit: '50' }),
      );
      if (!Array.isArray(payload.data)) return providerError('DEEZER_INVALID_RESPONSE', 'Deezer returned an invalid catalogue response', false);
      const tracks = payload.data
        .map((item) => this.mapTrack(item))
        .filter((item): item is ProviderTrack => item !== null);
      // The public Deezer endpoint can return a few unrelated promoted tracks
      // before genuinely matching results. Rank literal title/artist matches
      // ahead of those entries, retaining Deezer's ordering within each band.
      const words = q.toLocaleLowerCase().split(/\s+/).filter(Boolean);
      const relevance = (track: ProviderTrack): number => {
        const searchable = (track.title + ' ' + track.artist).toLocaleLowerCase();
        return words.filter(word => searchable.includes(word)).length;
      };
      const indexed = tracks.map((track, index) => ({
        track, index, score: relevance(track),
      }));
      indexed.sort((a, b) => b.score - a.score || a.index - b.index);
      const result = providerOk(
        indexed.map(item => item.track),
        'Track metadata supplied by Deezer; full-track playback is not granted by this API.',
      );
      await this.cache.set(key, result, 90);
      return result;
    } catch {
      return providerError('DEEZER_SEARCH_FAILED', 'Deezer catalogue search is temporarily unavailable', true);
    }
  }

  /**
   * OPTIONAL artist-page supplement. The Spotify artist remains authoritative.
   * A Deezer artist is eligible only when the public artist search finds one
   * unique, exact normalized name; ambiguous same-name artists are rejected.
   * This does not establish cross-service recording identity or media rights.
   */
  async getArtistSupplement(name: string): Promise<ProviderResult<DeezerArtistSupplement>> {
    if (!this.enabled) return providerUnsupported('DEEZER_NOT_CONFIGURED');
    const query = name.trim().replace(/\s+/g, ' ');
    if (query.length < 2 || query.length > 120) {
      return providerUnsupported('INVALID_ARTIST_QUERY');
    }
    const key = 'provider:deezer:artist-supplement:v1:' +
      encodeURIComponent(query.toLocaleLowerCase('en'));
    const cached = await this.cache.get<ProviderResult<DeezerArtistSupplement>>(key);
    if (cached) return cached;
    try {
      const search = await this.request<DeezerEnvelope<DeezerArtistRecord>>(
        this.url('search/artist', { q: query, limit: '25' }),
      );
      if (!Array.isArray(search.data)) {
        return providerError('DEEZER_ARTIST_SEARCH_INVALID', 'Invalid Deezer artist search', false);
      }
      const exact = search.data.filter(artist =>
        typeof artist.id === 'number' && Number.isSafeInteger(artist.id) &&
        artist.id > 0 && typeof artist.name === 'string' &&
        normalizeArtist(artist.name) === normalizeArtist(query));
      // Exact name alone is weak identity evidence. Never pick the first
      // of multiple exact artist identities and silently merge their data.
      const uniqueIds = [...new Set(exact.map(artist => artist.id!))];
      if (uniqueIds.length !== 1) {
        return providerUnsupported(uniqueIds.length ? 'DEEZER_ARTIST_AMBIGUOUS' :
          'DEEZER_ARTIST_NOT_MATCHED');
      }
      const artistId = uniqueIds[0];
      const [songsResult, albumsResult, relatedResult] = await Promise.allSettled([
        this.request<DeezerEnvelope<DeezerTrack>>(
          this.url('artist/' + artistId + '/top', { limit: '20' })),
        this.request<DeezerEnvelope<DeezerAlbumRecord>>(
          this.url('artist/' + artistId + '/albums', { limit: '30' })),
        this.request<DeezerEnvelope<DeezerArtistRecord>>(
          this.url('artist/' + artistId + '/related', { limit: '10' })),
      ]);
      const songsData = songsResult.status === 'fulfilled' &&
        Array.isArray(songsResult.value.data) ? songsResult.value.data : null;
      const albumData = albumsResult.status === 'fulfilled' &&
        Array.isArray(albumsResult.value.data) ? albumsResult.value.data : null;
      const relatedData = relatedResult.status === 'fulfilled' &&
        Array.isArray(relatedResult.value.data) ? relatedResult.value.data : null;
      const seenTracks = new Set<string>();
      const songs = (songsData ?? [])
        .filter(row => normalizeArtist(row.artist?.name ?? '') === normalizeArtist(query))
        .map(row => this.mapTrack(row))
        .filter((row): row is ProviderTrack => row !== null &&
          !seenTracks.has(row.providerTrackId) &&
          (seenTracks.add(row.providerTrackId), true))
        .map(row => ({ ...row, providerId: 'deezer' as const }));
      const seenAlbums = new Set<string>();
      const albums = (albumData ?? [])
        .filter(row => Number.isSafeInteger(row.id) && (row.id ?? 0) > 0 &&
          typeof row.title === 'string' && row.title.trim() &&
          (row.artist?.id === undefined || row.artist.id === artistId))
        .map(row => ({
          providerId: 'deezer' as const,
          id: String(row.id!),
          title: row.title!.trim(),
          type: row.record_type === 'single' ? 'single' as const : 'album' as const,
          releaseDate: typeof row.release_date === 'string' &&
            /^\d{4}-\d{2}-\d{2}$/.test(row.release_date)
            ? row.release_date : '',
          trackCount: typeof row.nb_tracks === 'number' ? row.nb_tracks : 0,
          artworkUrl: row.cover_big ?? row.cover_medium,
          url: 'https://www.deezer.com/album/' + row.id,
        }))
        .sort((a, b) => b.releaseDate.localeCompare(a.releaseDate))
        .filter(row => !seenAlbums.has(row.id) && (seenAlbums.add(row.id), true));
      const seenRelated = new Set<string>();
      const relatedArtists = (relatedData ?? [])
        .filter(row => typeof row.id === 'number' &&
          Number.isSafeInteger(row.id) && row.id > 0 && row.id !== artistId &&
          typeof row.name === 'string' && row.name.trim())
        .map(row => ({
          providerId: 'deezer' as const, id: String(row.id!),
          name: row.name!.trim(),
          imageUrl: row.picture_big ?? row.picture_medium,
          url: 'https://www.deezer.com/artist/' + row.id,
        }))
        .filter(row => !seenRelated.has(row.id) && (seenRelated.add(row.id), true));
      const result = providerOk<DeezerArtistSupplement>({
        matchedArtistId: String(artistId),
        matchedName: exact[0].name!,
        artistExtra: {
          fans: Number.isSafeInteger(exact[0].nb_fan) && (exact[0].nb_fan ?? -1) >= 0
            ? exact[0].nb_fan : undefined,
          albumCount: Number.isSafeInteger(exact[0].nb_album) && (exact[0].nb_album ?? -1) >= 0
            ? exact[0].nb_album : undefined,
          url: 'https://www.deezer.com/artist/' + artistId,
        },
        songs, albums, relatedArtists,
        songStatus: songsData === null ? 'unavailable' : 'ok',
        albumStatus: albumData === null ? 'unavailable' : 'ok',
        relatedStatus: relatedData === null ? 'unavailable' : 'ok',
      }, 'Deezer artist metadata only, never a full-song stream authorization');
      await this.cache.set(key, result, 120);
      return result;
    } catch {
      return providerError('DEEZER_ARTIST_SUPPLEMENT_FAILED',
        'Deezer artist metadata unavailable', true);
    }
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!/^\d{1,20}$/.test(providerTrackId)) return providerError('INVALID_DEEZER_TRACK_ID', 'Invalid Deezer track identifier', false);
    const key = `provider:deezer:track:v1:${providerTrackId}`;
    const cached = await this.cache.get<ProviderResult<ProviderTrack>>(key);
    if (cached) return cached;
    try {
      const track = this.mapTrack(await this.request<DeezerTrack>(this.url(`/track/${providerTrackId}`)));
      if (!track) return providerError('DEEZER_TRACK_NOT_FOUND', 'Deezer track metadata was not found', false);
      const result = providerOk(track, 'Track metadata supplied by Deezer; full-track playback is not granted by this API.');
      await this.cache.set(key, result, 300);
      return result;
    } catch {
      return providerError('DEEZER_TRACK_FAILED', 'Deezer track metadata is temporarily unavailable', true);
    }
  }

  async getAvailability(): Promise<ProviderResult<{ available: boolean }>> {
    return providerUnsupported('Deezer catalogue API access does not grant Breezze full-track streaming rights. Use an approved Deezer playback integration.');
  }

  async resolvePlayback(_request: ProviderPlaybackRequest): Promise<ProviderResult<ProviderPlaybackSource>> {
    return providerUnsupported('Deezer full-track playback requires an approved Deezer playback integration and user authorization.');
  }
}
