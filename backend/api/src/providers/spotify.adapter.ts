import { Injectable } from '@nestjs/common';
import * as crypto from 'node:crypto';
import {
  ProviderAdapter, ProviderCapabilities, ProviderTrack, ProviderPlaybackRequest,
  ProviderPlaybackSource,
} from './provider-adapter.interface';
import { ProviderCacheService } from './provider-cache.service';
import { ProviderResult, providerError, providerOk, providerUnsupported } from './provider-result';

const spotifyTrackId = /^[A-Za-z0-9]{22}$/;

interface SpotifyTrack {
  id?: string;
  name?: string;
  duration_ms?: number;
  is_playable?: boolean;
  is_local?: boolean;
  external_ids?: { isrc?: string };
  artists?: Array<{ id?: string; name?: string }>;
  album?: { images?: Array<{ url?: string }> };
}

interface SpotifySearchPayload {
  tracks?: { items?: SpotifyTrack[] };
  artists?: { items?: SpotifyArtist[] };
}

interface SpotifyArtist {
  id?: string;
  name?: string;
  images?: Array<{ url?: string }>;
  genres?: string[];
  followers?: { total?: number };
  popularity?: number;
  external_urls?: { spotify?: string };
}

interface SpotifyAlbum {
  id?: string;
  name?: string;
  album_type?: string;
  release_date?: string;
  total_tracks?: number;
  images?: Array<{ url?: string }>;
  external_urls?: { spotify?: string };
  artists?: Array<{ id?: string; name?: string }>;
}

export interface SpotifyArtistView {
  id: string;
  name: string;
  imageUrl?: string;
  url: string;
  genres: string[];
  followers?: number;
}

export interface SpotifyArtistRelease {
  id: string;
  title: string;
  type: string;
  releaseDate: string;
  trackCount: number;
  artworkUrl?: string;
  url: string;
}

export interface SpotifyArtistPage {
  artist: SpotifyArtistView;
  songs: ProviderTrack[];
  albums: SpotifyArtistRelease[];
  newReleases: SpotifyArtistRelease[];
  searchSuggestions: string[];
  tours: { status: 'unsupported'; events: [] };
  songStatus: 'ok' | 'unavailable';
  albumStatus: 'ok' | 'unavailable';
}

interface SpotifyTokenPayload {
  access_token?: string;
  token_type?: string;
  expires_in?: number;
}

/**
 * Spotify music discovery through the official Web API.
 *
 * Spotify never supplies raw audio, download grants, or a native Breezze
 * audio-engine source. Breezze must not claim it can play Spotify songs
 * without a separately approved in-app streaming integration.
 *
 * All client credentials and bearer tokens stay on this server, never on
 * Flutter or inside serialized provider results.
 */
@Injectable()
export class SpotifyAdapter implements ProviderAdapter {
  readonly providerId = 'spotify';
  readonly displayName = 'Spotify';
  readonly adapterVersion = '2026-11';
  readonly priority = 220;
  readonly capabilities: ProviderCapabilities = {
    search: true, metadata: true, availability: false,
    playback: false, download: false, albums: true,
    artists: true, playlists: true,
  };

  private token: { accessToken: string; expiresAt: number } | null = null;
  private tokenRequest: Promise<string | null> | null = null;

  constructor(private readonly cache: ProviderCacheService) {}

  get enabled(): boolean {
    return process.env.SPOTIFY_ENABLED !== 'false' &&
      Boolean(process.env.SPOTIFY_CLIENT_ID?.trim() &&
              process.env.SPOTIFY_CLIENT_SECRET?.trim());
  }

  private async acquireToken(): Promise<string | null> {
    if (!this.enabled) return null;
    if (this.token && this.token.expiresAt > Date.now() + 30_000) {
      return this.token.accessToken;
    }
    if (this.tokenRequest) return this.tokenRequest;
    this.tokenRequest = (async () => {
      try {
        const identity = Buffer.from(
          process.env.SPOTIFY_CLIENT_ID!.trim() + ':' +
          process.env.SPOTIFY_CLIENT_SECRET!.trim(),
        ).toString('base64');
        const response = await fetch('https://accounts.spotify.com/api/token', {
          method: 'POST', redirect: 'error',
          headers: {
            Authorization: 'Basic ' + identity,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: 'grant_type=client_credentials',
          signal: AbortSignal.timeout(6000),
        });
        if (!response.ok) return null;
        const payload = await response.json() as SpotifyTokenPayload;
        if (payload.token_type?.toLowerCase() !== 'bearer' ||
            typeof payload.access_token !== 'string' ||
            !payload.access_token || !Number.isFinite(payload.expires_in) ||
            (payload.expires_in ?? 0) < 60) return null;
        const token = payload.access_token;
        this.token = {
          accessToken: token,
          expiresAt: Date.now() + Math.floor(payload.expires_in! * 1000),
        };
        return token;
      } catch {
        return null;
      }
    })().finally(() => { this.tokenRequest = null; });
    return this.tokenRequest;
  }

  private async request<T>(path: string, params?: URLSearchParams):
    Promise<ProviderResult<T>> {
    if (!this.enabled) return providerUnsupported('SPOTIFY_NOT_CONFIGURED');
    const token = await this.acquireToken();
    if (!token) {
      return providerError('SPOTIFY_AUTH_UNAVAILABLE',
        'Spotify API authorization is unavailable', true);
    }
    try {
      const url = new URL('https://api.spotify.com/v1/' + path);
      if (params) url.search = params.toString();
      const response = await fetch(url, {
        redirect: 'error',
        headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' },
        signal: AbortSignal.timeout(6500),
      });
      if (response.status === 401) this.token = null;
      if (response.status === 429) {
        return providerError('SPOTIFY_RATE_LIMITED',
          'Spotify API request quota reached', true);
      }
      if (!response.ok) {
        return providerError('SPOTIFY_API_UNAVAILABLE',
          'Spotify music catalog is unavailable', response.status >= 500 || response.status === 401);
      }
      return providerOk(await response.json() as T);
    } catch {
      return providerError('SPOTIFY_NETWORK_UNAVAILABLE',
        'Spotify music catalog cannot be reached', true);
    }
  }

  private mapTrack(row: SpotifyTrack): ProviderTrack | null {
    if (!spotifyTrackId.test(row.id ?? '') || !row.name?.trim() ||
        !row.artists?.[0]?.name?.trim() || row.is_local === true ||
        row.is_playable === false) return null;
    const id = row.id!;
    const image = row.album?.images?.find(i =>
      typeof i.url === 'string' && i.url.startsWith('https://'));
    return {
      providerTrackId: id,
      title: row.name.trim(),
      artist: row.artists[0].name!.trim(),
      durationSec: Number.isFinite(row.duration_ms) && (row.duration_ms ?? 0) > 0
        ? Math.floor(row.duration_ms! / 1000) : undefined,
      artworkUrl: image?.url,
      isrc: row.external_ids?.isrc,
      // A Spotify link is NOT a native audio stream.
      sourceUrl: 'https://open.spotify.com/track/' + id,
    };
  }

  async search(query: string): Promise<ProviderResult<ProviderTrack[]>> {
    if (!this.enabled) return providerUnsupported('SPOTIFY_NOT_CONFIGURED');
    const q = query.trim();
    if (q.length < 2 || q.length > 120) return providerOk([]);
    const digest = crypto.createHash('sha256').update(q.toLowerCase()).digest('hex');
    const key = 'provider:spotify:search:v1:' + digest;
    const cached = await this.cache.get<ProviderResult<ProviderTrack[]>>(key);
    if (cached) return cached;
    const data = await this.request<SpotifySearchPayload>(
      'search', new URLSearchParams({ q, type: 'track', limit: '10' }),
    );
    if (data.kind !== 'ok') return data;
    if (!Array.isArray(data.value.tracks?.items)) {
      return providerError('SPOTIFY_INVALID_RESPONSE',
        'Spotify API returned an invalid search response');
    }
    const seen = new Set<string>();
    const result = providerOk(
      data.value.tracks.items
        .map(row => this.mapTrack(row))
        .filter((row): row is ProviderTrack =>
          row !== null && !seen.has(row.providerTrackId) &&
          (seen.add(row.providerTrackId), true)),
      'Spotify metadata only. Full Breezze playback requires separate rights.',
    );
    // Short-lived cache reduces Spotify development-mode API consumption.
    await this.cache.set(key, result, 90);
    return result;
  }


  private mapArtist(row: SpotifyArtist): SpotifyArtistView | null {
    if (!spotifyTrackId.test(row.id ?? '') || !row.name?.trim()) return null;
    const image = row.images?.find(item =>
      typeof item.url === 'string' && item.url.startsWith('https://'))?.url;
    return {
      id: row.id!,
      name: row.name.trim(),
      imageUrl: image,
      url: 'https://open.spotify.com/artist/' + row.id,
      genres: Array.isArray(row.genres) ? row.genres.filter(
        (name): name is string => typeof name === 'string').slice(0, 8) : [],
      followers: typeof row.followers?.total === 'number'
        ? row.followers.total : undefined,
    };
  }

  /** Official Spotify artist search. No Deezer or YouTube artist fallback. */
  async searchArtists(query: string): Promise<ProviderResult<SpotifyArtistView[]>> {
    const q = query.trim().replace(/\\s+/g, ' ');
    if (q.length < 2 || q.length > 120) return providerOk([]);
    const key = 'provider:spotify:artists:v1:' +
      crypto.createHash('sha256').update(q.toLowerCase()).digest('hex');
    const cached = await this.cache.get<ProviderResult<SpotifyArtistView[]>>(key);
    if (cached) return cached;
    const result = await this.request<SpotifySearchPayload>(
      'search', new URLSearchParams({ q, type: 'artist', limit: '10' }),
    );
    if (result.kind !== 'ok') return result;
    if (!Array.isArray(result.value.artists?.items)) {
      return providerError('SPOTIFY_ARTISTS_INVALID', 'Artist discovery returned invalid data');
    }
    const items = result.value.artists.items
      .map(item => this.mapArtist(item)).filter((a): a is SpotifyArtistView => a !== null);
    const norm = (name: string) => name.normalize('NFKC').toLowerCase().trim();
    const needle = norm(q);
    items.sort((a, b) => {
      const score = (name: string) => {
        const text = norm(name);
        return text === needle ? 3 : text.startsWith(needle) ? 2 :
          text.includes(needle) ? 1 : 0;
      };
      return score(b.name) - score(a.name);
    });
    const response = providerOk(items, 'Artist metadata supplied by Spotify');
    await this.cache.set(key, response, 120);
    return response;
  }

  private mapRelease(row: SpotifyAlbum, artistId: string): SpotifyArtistRelease | null {
    if (!spotifyTrackId.test(row.id ?? '') || !row.name?.trim() ||
        !row.artists?.some(artist => artist.id === artistId)) return null;
    const imageUrl = row.images?.find(img =>
      typeof img.url === 'string' && img.url.startsWith('https://'))?.url;
    const date = row.release_date ?? '';
    return {
      id: row.id!, title: row.name.trim(),
      type: row.album_type === 'single' ? 'single' : 'album',
      releaseDate: /^\\d{4}(-\\d{2}){0,2}$/.test(date) ? date : '',
      trackCount: typeof row.total_tracks === 'number' ? row.total_tracks : 0,
      artworkUrl: imageUrl,
      url: 'https://open.spotify.com/album/' + row.id,
    };
  }

  /**
   * Artist page uses Spotify ONLY for artist/catalog data. Spotify removed
   * /artists/:id/top-tracks in February 2026: use supported type=track search
   * and verify the artist ID on every returned recording. Tour data cannot be
   * obtained from Spotify; return an explicit empty/unsupported state.
   */
  async getArtistPage(id: string): Promise<ProviderResult<SpotifyArtistPage>> {
    if (!spotifyTrackId.test(id)) {
      return providerError('INVALID_SPOTIFY_ARTIST_ID', 'Invalid artist ID');
    }
    const key = 'provider:spotify:artist-page:v1:' + id;
    const cached = await this.cache.get<ProviderResult<SpotifyArtistPage>>(key);
    if (cached) return cached;
    const profile = await this.request<SpotifyArtist>('artists/' + id);
    if (profile.kind !== 'ok') return profile;
    const artist = this.mapArtist(profile.value);
    if (!artist || artist.id !== id) {
      return providerError('SPOTIFY_ARTIST_INVALID', 'Artist record is unavailable');
    }
    const [albumsResponse, songsResponse] = await Promise.all([
      this.request<{ items?: SpotifyAlbum[] }>(
        'artists/' + id + '/albums',
        new URLSearchParams({ include_groups: 'album,single', limit: '20' }),
      ),
      this.request<SpotifySearchPayload>(
        'search', new URLSearchParams({
          q: 'artist:"' + artist.name.replace(/"/g, '') + '"',
          type: 'track', limit: '10',
        }),
      ),
    ]);
    const releases = albumsResponse.kind === 'ok' && Array.isArray(albumsResponse.value.items)
      ? albumsResponse.value.items
          .map(row => this.mapRelease(row, id))
          .filter((row): row is SpotifyArtistRelease => row !== null)
      : [];
    // Unique album IDs; keep new releases first. No global /browse/new-releases.
    const seenAlbums = new Set<string>();
    const albums = releases
      .sort((a, b) => b.releaseDate.localeCompare(a.releaseDate))
      .filter(row => !seenAlbums.has(row.id) && (seenAlbums.add(row.id), true));
    const threshold = new Date();
    threshold.setUTCFullYear(threshold.getUTCFullYear() - 1);
    const cutoffDate = threshold.toISOString().slice(0, 10);
    const today = new Date().toISOString().slice(0, 10);
    const newReleases = albums.filter(item => {
      // Spotify can report YYYY, YYYY-MM or YYYY-MM-DD. A partial date
      // must not be promoted to a newly published release without proof.
      if (item.releaseDate.length !== 10) return false;
      return item.releaseDate >= cutoffDate && item.releaseDate <= today;
    });
    const seenSongs = new Set<string>();
    const songs = songsResponse.kind === 'ok' && Array.isArray(songsResponse.value.tracks?.items)
      ? songsResponse.value.tracks.items
        .filter(row => row.artists?.some(a => a.id === id))
        .map(row => this.mapTrack(row))
        .filter((row): row is ProviderTrack => row !== null &&
          !seenSongs.has(row.providerTrackId) &&
          (seenSongs.add(row.providerTrackId), true))
      : [];
    const searchSuggestions = [
      ...albums.slice(0, 3).map(album => album.title),
      ...artist.genres.slice(0, 2).map(genre => artist.name + ' ' + genre),
    ].filter((name, index, arr) => arr.indexOf(name) === index);
    const response = providerOk<SpotifyArtistPage>({
      artist, songs, albums, newReleases, searchSuggestions,
      tours: { status: 'unsupported', events: [] },
      songStatus: songsResponse.kind === 'ok' ? 'ok' : 'unavailable',
      albumStatus: albumsResponse.kind === 'ok' ? 'ok' : 'unavailable',
    }, 'Artist metadata supplied by Spotify; full-track playback is not granted');
    await this.cache.set(key, response, 120);
    return response;
  }

  /** Spotify album detail, with native Spotify metadata only (no stream URLs). */
  async getAlbumPage(id: string): Promise<ProviderResult<{
    album: SpotifyArtistRelease;
    tracks: ProviderTrack[];
    tracksStatus: 'ok' | 'unavailable';
  }>> {
    if (!spotifyTrackId.test(id)) {
      return providerError('INVALID_SPOTIFY_ALBUM_ID', 'Invalid Spotify album ID');
    }
    const key = 'provider:spotify:album-page:v1:' + id;
    const cached = await this.cache.get<ProviderResult<{
      album: SpotifyArtistRelease; tracks: ProviderTrack[];
      tracksStatus: 'ok' | 'unavailable';
    }>>(key);
    if (cached) return cached;
    const albumResponse = await this.request<SpotifyAlbum>('albums/' + id);
    if (albumResponse.kind !== 'ok') return albumResponse;
    const creditedArtist = albumResponse.value.artists?.find(a => spotifyTrackId.test(a.id ?? ''));
    const album = creditedArtist
      ? this.mapRelease(albumResponse.value, creditedArtist.id!) : null;
    if (!album) return providerError('SPOTIFY_ALBUM_INVALID', 'Album metadata unavailable');
    const listing = await this.request<{ items?: SpotifyTrack[] }>(
      'albums/' + id + '/tracks', new URLSearchParams({ limit: '50' }),
    );
    const seen = new Set<string>();
    const tracks = listing.kind === 'ok' && Array.isArray(listing.value.items)
      ? listing.value.items
        .map(row => this.mapTrack({
          ...row, album: { images: albumResponse.value.images },
        }))
        .filter((row): row is ProviderTrack => row !== null &&
          !seen.has(row.providerTrackId) &&
          (seen.add(row.providerTrackId), true))
      : [];
    const response = providerOk({
      album, tracks,
      tracksStatus: listing.kind === 'ok' ? 'ok' as const : 'unavailable' as const,
    }, 'Spotify album metadata only');
    await this.cache.set(key, response, 120);
    return response;
  }

  async getTrack(providerTrackId: string): Promise<ProviderResult<ProviderTrack>> {
    if (!spotifyTrackId.test(providerTrackId)) {
      return providerError('INVALID_SPOTIFY_TRACK_ID', 'Invalid Spotify track ID');
    }
    const result = await this.request<SpotifyTrack>('tracks/' + providerTrackId);
    if (result.kind !== 'ok') return result;
    const track = this.mapTrack(result.value);
    if (!track) return providerError('SPOTIFY_TRACK_UNAVAILABLE',
      'This track cannot be played in the current catalog');
    return providerOk(track, 'Spotify metadata only; no Breezze full-stream grant.');
  }

  async getAvailability(): Promise<ProviderResult<{available: boolean}>> {
    return providerUnsupported('Spotify does not grant native third-party audio streams.');
  }

  async resolvePlayback(_request: ProviderPlaybackRequest):
    Promise<ProviderResult<ProviderPlaybackSource>> {
    return providerUnsupported('Spotify public Web API does not provide raw Breezze audio streams.');
  }
}
