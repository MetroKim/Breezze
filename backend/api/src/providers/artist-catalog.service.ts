import { Injectable } from '@nestjs/common';
import { DeezerAdapter } from './deezer.adapter';
import { SpotifyAdapter, SpotifyArtistPage } from './spotify.adapter';
import { ProviderResult, providerOk } from './provider-result';

export interface ArtistPageWithFallback extends SpotifyArtistPage {
  /** Each section is owned by exactly one provider; never merge audio URLs. */
  songSource: 'spotify' | 'deezer';
  albumSource: 'spotify' | 'deezer';
  relatedArtists: Array<{
    providerId: 'deezer';
    id: string;
    name: string;
    imageUrl?: string;
    url: string;
  }>;
  relatedStatus: 'ok' | 'unavailable' | 'disabled';
  sourceMatch: 'spotify_only' | 'unique_exact_name';
}

@Injectable()
export class ArtistCatalogService {
  constructor(
    private readonly spotify: SpotifyAdapter,
    private readonly deezer: DeezerAdapter,
  ) {}

  /**
   * Spotify owns the verified identity, portrait and artist profile.
   * Deezer can only fill a missing WHOLE section after unique, exact-name
   * matching. This never authorizes streaming or rewrites a Spotify ID.
   *
   * Spotify's branding policy restricts adjacent competing-service content.
   * In production fallback requires explicit rights/compliance approval.
   */
  async getArtistPage(spotifyArtistId: string):
    Promise<ProviderResult<ArtistPageWithFallback>> {
    const upstream = await this.spotify.getArtistPage(spotifyArtistId);
    if (upstream.kind !== 'ok') return upstream;

    const primary = upstream.value;
    const base: ArtistPageWithFallback = {
      ...primary,
      songSource: 'spotify',
      albumSource: 'spotify',
      relatedArtists: [],
      relatedStatus: 'disabled',
      sourceMatch: 'spotify_only',
    };
    // Fail CLOSED in unknown deployment environments. Only explicit
    // development/test or a documented production approval may enable this.
    const permitted = process.env.ARTIST_DEEZER_FALLBACK_APPROVED === 'true' ||
      process.env.NODE_ENV === 'development' || process.env.NODE_ENV === 'test';
    if (!permitted) return providerOk(base, upstream.attribution);

    // Get artist-related suggestions that Spotify's development API does not
    // offer. Also fill an EMPTY or failed song/album section, not a fraction
    // of it. The upstream Deezer call is bounded and Redis-cached.
    const supplemental = await this.deezer.getArtistSupplement(primary.artist.name);
    if (supplemental.kind !== 'ok') return providerOk(base, upstream.attribution);
    const deezer = supplemental.value;

    const hasSpotifySongs = primary.songs.length > 0;
    const hasSpotifyAlbums = primary.albums.length > 0;
    const songs = hasSpotifySongs ? primary.songs : deezer.songs;
    const albums = hasSpotifyAlbums ? primary.albums : deezer.albums;
    const now = new Date();
    const cutoff = new Date(now);
    cutoff.setUTCFullYear(now.getUTCFullYear() - 1);
    const since = cutoff.toISOString().slice(0, 10);
    const today = now.toISOString().slice(0, 10);
    const releases = hasSpotifyAlbums ? primary.newReleases :
      deezer.albums.filter(album => album.releaseDate >= since &&
        album.releaseDate <= today);
    // Related artists are Deezer artist-level suggestions, clearly labeled
    // as such on the client. Never present them as Spotify recommendations.
    return providerOk<ArtistPageWithFallback>({
      ...primary,
      songs, albums, newReleases: releases,
      songSource: hasSpotifySongs || deezer.songs.length === 0 ? 'spotify' : 'deezer',
      albumSource: hasSpotifyAlbums || deezer.albums.length === 0 ? 'spotify' : 'deezer',
      songStatus: hasSpotifySongs || deezer.songStatus === 'ok' ? 'ok' : primary.songStatus,
      albumStatus: hasSpotifyAlbums || deezer.albumStatus === 'ok' ? 'ok' : primary.albumStatus,
      relatedArtists: deezer.relatedArtists,
      relatedStatus: deezer.relatedStatus,
      sourceMatch: 'unique_exact_name',
    }, upstream.attribution);
  }
}
