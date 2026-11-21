import { Injectable } from '@nestjs/common';

type AppleFeedItem = {
  id?: string;
  name?: string;
  artistName?: string;
  artworkUrl100?: string;
  url?: string;
  releaseDate?: string;
  genres?: { name?: string }[];
};

type AppleFeedResponse = {
  feed?: { title?: string; results?: AppleFeedItem[] };
};

@Injectable()
export class DiscoveryService {
  private country(value?: string): string {
    const normalized = (value ?? 'us').trim().toLowerCase();
    return /^[a-z]{2}$/.test(normalized) ? normalized : 'us';
  }

  private async appleFeed(kind: 'songs' | 'albums', feed: 'most-played' | 'new-releases', country?: string) {
    const territory = this.country(country);
    const url = `https://rss.applemarketingtools.com/api/v2/${territory}/music/${feed}/100/${kind}.json`;
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) {
      throw new Error(`APPLE_RSS_HTTP_${response.status}`);
    }
    const payload = await response.json() as AppleFeedResponse;
    const results = payload.feed?.results;
    if (!Array.isArray(results)) throw new Error('APPLE_RSS_INVALID_RESPONSE');
    return {
      source: 'Apple Music RSS',
      sourceUrl: url,
      territory: territory.toUpperCase(),
      title: payload.feed?.title ?? (feed === 'most-played' ? 'Top Songs' : 'New Releases'),
      fetchedAt: new Date().toISOString(),
      items: results.map((item, index) => ({
        id: item.id ?? null,
        title: item.name ?? 'Untitled',
        artist: item.artistName ?? 'Unknown artist',
        artworkUrl: item.artworkUrl100 ?? null,
        releaseDate: item.releaseDate ?? null,
        genres: (item.genres ?? []).map((genre) => genre.name).filter(Boolean),
        rank: feed === 'most-played' ? index + 1 : null,
        url: item.url ?? null,
        playback: 'external_catalog_only',
      })),
    };
  }

  songsChart(country?: string) {
    return this.appleFeed('songs', 'most-played', country);
  }

  newReleases(country?: string) {
    return this.appleFeed('albums', 'new-releases', country);
  }

  async artistAlbums(artistId: string) {
    if (!/^\\d{1,20}$/.test(artistId)) throw new Error('INVALID_APPLE_ARTIST_ID');
    const url = new URL('https://itunes.apple.com/lookup');
    url.searchParams.set('id', artistId);
    url.searchParams.set('entity', 'album');
    url.searchParams.set('limit', '200');
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error(`ITUNES_LOOKUP_HTTP_${response.status}`);
    const payload = await response.json() as { results?: Record<string, unknown>[] };
    const rows = Array.isArray(payload.results) ? payload.results : [];
    const artist = rows.find((row) => row.wrapperType === 'artist');
    const albums = rows.filter((row) => row.wrapperType === 'collection');
    return {
      source: 'Apple iTunes Search API',
      artist: artist ? { id: artist.artistId, name: artist.artistName } : null,
      fetchedAt: new Date().toISOString(),
      items: albums.map((album) => ({
        id: album.collectionId,
        title: album.collectionName,
        artist: album.artistName,
        artworkUrl: album.artworkUrl100,
        releaseDate: album.releaseDate,
        trackCount: album.trackCount,
        url: album.collectionViewUrl,
        playback: 'external_catalog_only',
      })),
    };
  }

  async albumTracks(albumId: string) {
    if (!/^\\d{1,20}$/.test(albumId)) throw new Error('INVALID_APPLE_ALBUM_ID');
    const url = new URL('https://itunes.apple.com/lookup');
    url.searchParams.set('id', albumId);
    url.searchParams.set('entity', 'song');
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error(`ITUNES_LOOKUP_HTTP_${response.status}`);
    const payload = await response.json() as { results?: Record<string, unknown>[] };
    const rows = Array.isArray(payload.results) ? payload.results : [];
    const album = rows.find((row) => row.wrapperType === 'collection');
    const tracks = rows.filter((row) => row.wrapperType === 'track');
    return {
      source: 'Apple iTunes Search API',
      album: album ? { id: album.collectionId, title: album.collectionName, artist: album.artistName } : null,
      fetchedAt: new Date().toISOString(),
      items: tracks.map((track) => ({
        id: track.trackId,
        title: track.trackName,
        artist: track.artistName,
        artworkUrl: track.artworkUrl100,
        durationMs: track.trackTimeMillis,
        trackNumber: track.trackNumber,
        url: track.trackViewUrl,
        previewUrl: track.previewUrl,
        playback: 'preview_only',
      })),
    };
  }

  async searchArtists(query: string) {
    const q = query.trim().slice(0, 100);
    if (q.length < 2) return { source: 'Apple iTunes Search API', items: [] };
    const url = new URL('https://itunes.apple.com/search');
    url.searchParams.set('term', q);
    url.searchParams.set('entity', 'musicArtist');
    url.searchParams.set('limit', '15');
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error(`ITUNES_SEARCH_HTTP_${response.status}`);
    const payload = await response.json() as { results?: Record<string, unknown>[] };
    return {
      source: 'Apple iTunes Search API',
      items: (payload.results ?? []).map((artist) => ({
        id: artist.artistId,
        name: artist.artistName,
        url: artist.artistLinkUrl,
      })),
    };
  }
}
