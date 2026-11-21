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
    const url = `https://rss.marketingtools.apple.com/api/v2/${territory}/music/${feed}/100/${kind}.json`;
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


  async dailyTop100(country?: string) {
    const token = process.env.APPLE_MUSIC_DEVELOPER_TOKEN;
    if (!token) throw new Error('APPLE_MUSIC_API_NOT_CONFIGURED');
    const territory = this.country(country);
    const url = new URL(`https://api.music.apple.com/v1/catalog/${territory}/charts`);
    url.searchParams.set('types', 'songs');
    url.searchParams.set('with', 'dailyGlobalTopCharts');
    url.searchParams.set('limit', '100');
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`APPLE_MUSIC_CHART_HTTP_${response.status}`);
    const payload = await response.json() as {
      results?: { songs?: { name?: string; data?: Record<string, any>[] }[] };
    };
    const charts = payload.results?.songs ?? [];
    const chart = charts[0];
    const items = chart?.data ?? [];
    return {
      source: 'Apple Music API',
      title: chart?.name ?? 'Daily Global Top Songs',
      territory: territory.toUpperCase(),
      fetchedAt: new Date().toISOString(),
      items: items.map((item, index) => {
        const attributes = item.attributes ?? {};
        const artwork = attributes.artwork?.url;
        return {
          id: item.id ?? null,
          title: attributes.name ?? 'Untitled',
          artist: attributes.artistName ?? 'Unknown artist',
          artworkUrl: typeof artwork === 'string'
            ? artwork.replace('{w}', '300').replace('{h}', '300')
            : null,
          rank: index + 1,
          releaseDate: attributes.releaseDate ?? null,
          url: attributes.url ?? null,
          playback: 'external_catalog_only',
        };
      }),
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



  async musicVideos(query = 'official music video') {
    const apiKey = process.env.YOUTUBE_DATA_API_KEY;
    const approvedChannels = (process.env.YOUTUBE_OFFICIAL_CHANNEL_IDS ?? '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean);
    if (!apiKey || approvedChannels.length === 0) {
      throw new Error('YOUTUBE_VIDEO_PROVIDER_NOT_CONFIGURED');
    }
    const url = new URL('https://www.googleapis.com/youtube/v3/search');
    url.searchParams.set('part', 'snippet');
    url.searchParams.set('type', 'video');
    url.searchParams.set('videoCategoryId', '10');
    url.searchParams.set('videoEmbeddable', 'true');
    url.searchParams.set('order', 'viewCount');
    url.searchParams.set('maxResults', '50');
    url.searchParams.set('q', query.trim().slice(0, 100) || 'official music video');
    url.searchParams.set('key', apiKey);
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error(`YOUTUBE_DATA_HTTP_${response.status}`);
    const payload = await response.json() as {
      items?: { id?: { videoId?: string }; snippet?: {
        title?: string; channelId?: string; channelTitle?: string;
        publishedAt?: string; thumbnails?: { high?: { url?: string }; medium?: { url?: string } };
      } }[];
    };
    const items = (payload.items ?? []).filter((item) =>
      item.snippet?.channelId && approvedChannels.includes(item.snippet.channelId),
    );
    return {
      source: 'YouTube Data API',
      verifiedChannelPolicy: 'Only channel IDs configured in YOUTUBE_OFFICIAL_CHANNEL_IDS are shown.',
      fetchedAt: new Date().toISOString(),
      items: items.map((item) => ({
        id: item.id?.videoId ?? null,
        title: item.snippet?.title ?? 'Untitled video',
        artist: item.snippet?.channelTitle ?? 'Verified channel',
        channelId: item.snippet?.channelId ?? null,
        publishedAt: item.snippet?.publishedAt ?? null,
        artworkUrl: item.snippet?.thumbnails?.high?.url ?? item.snippet?.thumbnails?.medium?.url ?? null,
        url: item.id?.videoId ? `https://www.youtube.com/watch?v=${item.id.videoId}` : null,
        playback: 'external_youtube_only',
      })),
    };
  }

  async concerts(country = 'TZ', city?: string) {
    const apiKey = process.env.JAMBASE_DATA_API_KEY;
    if (!apiKey) throw new Error('JAMBASE_PROVIDER_NOT_CONFIGURED');
    const territory = this.country(country).toUpperCase();
    const url = new URL('https://api.data.jambase.com/v3/events');
    url.searchParams.set('geoCountryIso2', territory);
    url.searchParams.set('eventType', 'concerts');
    url.searchParams.set('eventDateFrom', new Date().toISOString().slice(0, 10));
    url.searchParams.set('perPage', '50');
    url.searchParams.set('page', '1');
    if (city?.trim()) url.searchParams.set('geoCityName', city.trim().slice(0, 80));
    const response = await fetch(url, {
      headers: {
        Authorization: `Bearer ${apiKey}`,
        Accept: 'application/json',
        'User-Agent': 'Breezze/0.1 (+https://breezze.app)',
      },
      signal: AbortSignal.timeout(6000),
    });
    if (!response.ok) throw new Error(`JAMBASE_EVENTS_HTTP_${response.status}`);
    const payload = await response.json() as {
      events?: Record<string, any>[];
      pagination?: Record<string, unknown>;
    };
    return {
      source: 'JamBase Data',
      attribution: 'Concert data provided by JamBase',
      territory,
      city: city?.trim() || null,
      fetchedAt: new Date().toISOString(),
      pagination: payload.pagination ?? null,
      items: (payload.events ?? []).filter((event) => event.deletionStatus == null).map((event) => {
        const performers = Array.isArray(event.performer) ? event.performer : [];
        const location = event.location ?? {};
        const address = location.address ?? {};
        const offers = Array.isArray(event.offers) ? event.offers : [];
        const ticket = offers.find((offer) => typeof offer.url === 'string');
        return {
          id: event.identifier ?? null,
          title: event.name ?? 'Live music event',
          artist: performers.map((performer: Record<string, any>) => performer.name).filter(Boolean).join(', '),
          date: event.startDate ?? null,
          venue: location.name ?? null,
          city: address.addressLocality ?? city ?? null,
          country: address.addressCountry?.name ?? territory,
          artworkUrl: event.image ?? null,
          url: event.url ?? null,
          ticketUrl: ticket?.url ?? null,
        };
      }),
    };
  }

  async searchTracks(query: string) {
    const q = query.trim().slice(0, 120);
    if (q.length < 2) return { source: 'Apple iTunes Search API', items: [] };
    const url = new URL('https://itunes.apple.com/search');
    url.searchParams.set('term', q);
    url.searchParams.set('entity', 'song');
    url.searchParams.set('limit', '30');
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw new Error(`ITUNES_TRACK_SEARCH_HTTP_${response.status}`);
    const payload = await response.json() as { results?: Record<string, unknown>[] };
    return {
      source: 'Apple iTunes Search API',
      items: (payload.results ?? []).map((track) => ({
        id: track.trackId,
        title: track.trackName,
        artist: track.artistName,
        artistId: track.artistId,
        albumId: track.collectionId,
        albumTitle: track.collectionName,
        albumUrl: track.collectionViewUrl,
        artworkUrl: track.artworkUrl100,
        releaseDate: track.releaseDate,
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
