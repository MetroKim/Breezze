import { Injectable } from '@nestjs/common';

type DeezerArtist = {
  id?: number; name?: string; link?: string;
  picture_big?: string; picture_medium?: string;
};
type DeezerAlbum = {
  id?: number; title?: string; link?: string; release_date?: string;
  cover_big?: string; cover_medium?: string; nb_tracks?: number;
  record_type?: string; artist?: DeezerArtist;
  genres?: { data?: { name?: string }[] };
  tracks?: { data?: DeezerTrack[] };
};
type DeezerTrack = {
  id?: number; title?: string; link?: string; duration?: number;
  preview?: string; track_position?: number; artist?: DeezerArtist;
  album?: DeezerAlbum;
};
type DeezerPage<T> = { data?: T[]; total?: number; error?: { message?: string } };

@Injectable()
export class DiscoveryService {
  private readonly deezerCache = new Map<string, { until: number; payload: unknown }>();

  private country(value?: string): string {
    const normalized = (value ?? 'us').trim().toLowerCase();
    return /^[a-z]{2}$/.test(normalized) && normalized !== 'ww' ? normalized : 'us';
  }

  // The public Deezer chart is global; never label its results as a country-
  // specific chart based on the requesting listener's location.
  private async deezer<T>(
    path: string,
    params: Record<string, string> = {},
    ttlMs = 0,
  ): Promise<T> {
    const url = new URL(path.replace(/^\//, ''), 'https://api.deezer.com/');
    for (const [name, value] of Object.entries(params)) url.searchParams.set(name, value);
    const key = url.toString();
    const cached = this.deezerCache.get(key);
    if (cached && cached.until > Date.now()) return cached.payload as T;
    let response: Response | null = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        response = await fetch(url, {
          headers: { accept: 'application/json', 'user-agent': 'Breezze/1.0' },
          signal: AbortSignal.timeout(5000),
        });
      } catch (error) {
        if (attempt === 1) throw error;
        continue;
      }
      if (response.ok) break;
      if (attempt === 0 && (response.status === 429 || response.status >= 500)) continue;
      throw new Error('DEEZER_HTTP_' + response.status);
    }
    if (!response?.ok) throw new Error('DEEZER_UNAVAILABLE');
    const payload = await response.json() as T & { error?: { message?: string } };
    if (payload.error) throw new Error('DEEZER_API_REJECTED_REQUEST');
    if (ttlMs > 0) {
      if (this.deezerCache.size >= 120) this.deezerCache.clear();
      this.deezerCache.set(key, { until: Date.now() + ttlMs, payload });
    }
    return payload;
  }

  private page<T>(payload: DeezerPage<T>): T[] {
    if (!Array.isArray(payload.data)) throw new Error('DEEZER_INVALID_RESPONSE');
    return payload.data;
  }

  private previewUrl(value?: string): string | null {
    if (!value) return null;
    try {
      const url = new URL(value);
      return url.protocol === 'https:' && url.hostname.endsWith('.dzcdn.net')
        ? url.toString() : null;
    } catch { return null; }
  }

  private trackItem(track: DeezerTrack, index?: number) {
    if (!Number.isSafeInteger(track.id) || !track.id ||
        !track.title?.trim() || !track.artist?.name?.trim()) return null;
    const previewUrl = this.previewUrl(track.preview);
    return {
      id: String(track.id),
      title: track.title.trim(),
      artist: track.artist.name.trim(),
      artistId: track.artist.id ?? null,
      albumId: track.album?.id ?? null,
      albumTitle: track.album?.title ?? null,
      albumUrl: track.album?.link ?? null,
      artworkUrl: track.album?.cover_big ?? track.album?.cover_medium ?? null,
      durationMs: Number.isSafeInteger(track.duration) && (track.duration ?? 0) > 0
        ? track.duration! * 1000 : null,
      trackNumber: track.track_position ?? null,
      url: track.link ?? null,
      previewUrl,
      rank: index == null ? null : index + 1,
      playback: previewUrl ? 'preview_only' : 'external_catalog_only',
    };
  }

  private albumItem(album: DeezerAlbum) {
    if (!Number.isSafeInteger(album.id) || !album.id || !album.title?.trim()) return null;
    return {
      id: String(album.id),
      title: album.title.trim(),
      artist: album.artist?.name ?? 'Unknown artist',
      artworkUrl: album.cover_big ?? album.cover_medium ?? null,
      releaseDate: album.release_date ?? null,
      trackCount: album.nb_tracks ?? null,
      genres: album.genres?.data?.map(g => g.name).filter((g): g is string => !!g) ?? [],
      isCompilation: album.record_type === 'compilation',
      url: album.link ?? null,
      playback: 'external_catalog_only',
    };
  }

  async songsChart(_country?: string) {
    const rows = this.page(await this.deezer<DeezerPage<DeezerTrack>>(
      'chart/0/tracks', { limit: '100' }, 10 * 60_000,
    ));
    return {
      source: 'Deezer',
      sourceUrl: 'https://api.deezer.com/chart/0/tracks',
      territory: 'GLOBAL',
      title: 'Deezer Global Top Tracks',
      fetchedAt: new Date().toISOString(),
      items: rows.map((row, index) => this.trackItem(row, index))
        .filter((row): row is NonNullable<typeof row> => row !== null),
    };
  }

  async dailyTop100(country?: string) {
    const chart = await this.songsChart(country);
    return {
      ...chart,
      title: 'Deezer Global Top Tracks (not a daily regional Top 100)',
      chartType: 'deezer_global_chart' as const,
      dailyTop100Available: false,
    };
  }

  // Deezer's global trending-album chart has no release dates. Verify real
  // album release_date fields individually; never infer that chart placement
  // means "new release".
  async newReleases(_country?: string) {
    const rows = this.page(await this.deezer<DeezerPage<DeezerAlbum>>(
      'chart/0/albums', { limit: '30' }, 10 * 60_000,
    ));
    const relevant = rows.slice(0, 18).filter(row => Number.isSafeInteger(row.id));
    const hydrated = await Promise.allSettled(relevant.map(row =>
      this.deezer<DeezerAlbum>('album/' + row.id, {}, 10 * 60_000),
    ));
    const now = Date.now();
    const earliest = now - 30 * 86400000;
    const items = hydrated.flatMap((result) => {
      if (result.status !== 'fulfilled') return [];
      const item = this.albumItem(result.value);
      const release = Date.parse(result.value.release_date ?? '');
      return item && Number.isFinite(release) && release >= earliest && release <= now
        ? [item] : [];
    }).sort((a, b) =>
      Date.parse(b.releaseDate ?? '') - Date.parse(a.releaseDate ?? ''),
    );
    return {
      source: 'Deezer',
      sourceUrl: 'https://api.deezer.com/chart/0/albums',
      territory: 'GLOBAL',
      title: 'Recently released albums appearing on Deezer global charts',
      fetchedAt: new Date().toISOString(),
      items,
    };
  }

  async recentChartReleases(kind: 'songs' | 'albums', country?: string) {
    const releases = await this.newReleases(country);
    if (kind === 'albums') return releases;
    // "Latest Songs" lists tracks FROM independently dated new albums, not
    // tracks falsely presumed to have been first released this month.
    const recent = releases.items.slice(0, 6);
    const pages = await Promise.allSettled(recent.map(album =>
      this.albumTracks(album.id),
    ));
    const seen = new Set<string>();
    const items = pages.flatMap((page, index) => {
      if (page.status !== 'fulfilled') return [];
      return page.value.items.map(track => ({
        ...track,
        releaseDate: recent[index].releaseDate,
        rank: null,
      })).filter(track => {
        if (seen.has(track.id)) return false;
        seen.add(track.id);
        return true;
      });
    });
    return { ...releases,
      title: 'Tracks from recently released Deezer chart albums',
      items,
    };
  }

  async artistAlbums(artistId: string) {
    if (!/^\d{1,20}$/.test(artistId)) throw new Error('INVALID_DEEZER_ARTIST_ID');
    const [artist, albums] = await Promise.all([
      this.deezer<DeezerArtist>('artist/' + artistId, {}, 5 * 60_000),
      this.deezer<DeezerPage<DeezerAlbum>>('artist/' + artistId + '/albums', { limit: '100' }, 5 * 60_000),
    ]);
    const items = this.page(albums).map(row =>
      this.albumItem({ ...row, artist: row.artist ?? artist }),
    ).filter((row): row is NonNullable<typeof row> => row !== null);
    return {
      source: 'Deezer',
      artist: { id: String(artist.id ?? artistId), name: artist.name ?? null },
      fetchedAt: new Date().toISOString(),
      items,
    };
  }

  async albumTracks(albumId: string) {
    if (!/^\d{1,20}$/.test(albumId)) throw new Error('INVALID_DEEZER_ALBUM_ID');
    const album = await this.deezer<DeezerAlbum>('album/' + albumId, {}, 5 * 60_000);
    if (!album.id) throw new Error('DEEZER_ALBUM_UNAVAILABLE');
    const trackRows = Array.isArray(album.tracks?.data)
      ? album.tracks!.data!
      : this.page(await this.deezer<DeezerPage<DeezerTrack>>(
        'album/' + albumId + '/tracks', { limit: '100' }, 5 * 60_000,
      ));
    const items = trackRows.map(track =>
      this.trackItem({ ...track, album: track.album ?? album }),
    ).filter((row): row is NonNullable<typeof row> => row !== null);
    return {
      source: 'Deezer',
      album: this.albumItem(album),
      fetchedAt: new Date().toISOString(),
      items,
    };
  }

  async musicVideoForSong(id: string) {
    const base = process.env.YTMUSIC_API_URL ?? 'http://127.0.0.1:8000';
    const response = await fetch(new URL(`/tracks/${encodeURIComponent(id)}/music-video`, base), {
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error('YTMUSIC_COUNTERPART_UNAVAILABLE');
    const payload = await response.json() as { videoId?: unknown };
    if (payload.videoId === null) return { videoId: null };
    if (typeof payload.videoId !== 'string' || !/^[A-Za-z0-9_-]{11}$/.test(payload.videoId)) {
      throw new Error('YTMUSIC_INVALID_RESPONSE');
    }
    return { videoId: payload.videoId };
  }

  async musicVideos(query = 'official music video') {
    const q = query.trim().slice(0, 100) || 'official music video';
    const baseUrl = (process.env.YTMUSIC_API_URL ?? 'http://127.0.0.1:8000').replace(/\/$/, '');
    try {
      const url = new URL('/videos', baseUrl);
      url.searchParams.set('q', q);
      url.searchParams.set('limit', '25');
      const response = await fetch(url, { signal: AbortSignal.timeout(4500) });
      if (!response.ok) throw new Error(`YTMUSIC_VIDEO_HTTP_${response.status}`);
      const payload = await response.json() as {
        source?: string;
        videos?: {
          videoId?: string; title?: string; artist?: string; artworkUrl?: string;
          durationSec?: number | null; videoType?: string; classification?: string; url?: string;
        }[];
      };
      if (!Array.isArray(payload.videos)) throw new Error('YTMUSIC_VIDEO_INVALID_RESPONSE');
      const seenIds = new Set<string>();
      return {
        source: payload.source ?? 'YouTube Music via ytmusicapi',
        classification: 'YouTube Music Original Music Video (OMV)',
        fetchedAt: new Date().toISOString(),
        items: payload.videos.filter((video) => {
          if (video == null || typeof video.videoId !== 'string' ||
              !/^[A-Za-z0-9_-]{11}$/.test(video.videoId) || seenIds.has(video.videoId)) {
            return false;
          }
          seenIds.add(video.videoId);
          return true;
        }).map((video) => ({
          id: video.videoId!,
          title: video.title ?? 'Untitled video',
          artist: video.artist ?? 'Unknown artist',
          artworkUrl: video.artworkUrl ?? null,
          durationSec: video.durationSec ?? null,
          videoType: video.videoType ?? null,
          classification: video.classification ?? null,
          url: video.url ?? null,
          playback: 'external_youtube_only',
        })),
      };
    } catch (ytMusicError) {
      // Optional fallback: the official Data API is used only when an API key
      // and manually reviewed channel allowlist have both been configured.
      const apiKey = process.env.YOUTUBE_DATA_API_KEY;
      const approvedChannels = (process.env.YOUTUBE_OFFICIAL_CHANNEL_IDS ?? '')
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean);
      if (!apiKey || approvedChannels.length === 0) throw ytMusicError;

      const url = new URL('https://www.googleapis.com/youtube/v3/search');
      url.searchParams.set('part', 'snippet');
      url.searchParams.set('type', 'video');
      url.searchParams.set('videoCategoryId', '10');
      url.searchParams.set('videoEmbeddable', 'true');
      url.searchParams.set('order', 'viewCount');
      url.searchParams.set('maxResults', '50');
      url.searchParams.set('q', q);
      url.searchParams.set('key', apiKey);
      const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
      if (!response.ok) throw new Error(`YOUTUBE_DATA_HTTP_${response.status}`);
      const payload = await response.json() as {
        items?: { id?: { videoId?: string }; snippet?: {
          title?: string; channelId?: string; channelTitle?: string;
          publishedAt?: string; thumbnails?: { high?: { url?: string }; medium?: { url?: string } };
        } }[];
      };
      const items = (Array.isArray(payload.items) ? payload.items : []).filter((item) =>
        item != null && typeof item.id?.videoId === 'string' &&
        /^[A-Za-z0-9_-]{11}$/.test(item.id.videoId) &&
        item.snippet?.channelId && approvedChannels.includes(item.snippet.channelId),
      );
      return {
        source: 'YouTube Data API fallback',
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
    if (q.length < 2) return { source: 'Deezer', items: [] };
    const rows = this.page(await this.deezer<DeezerPage<DeezerTrack>>(
      'search/track', { q, limit: '30' }, 60_000,
    ));
    return {
      source: 'Deezer',
      items: rows.map(row => this.trackItem(row))
        .filter((row): row is NonNullable<typeof row> => row !== null),
    };
  }

  async searchArtists(query: string) {
    const q = query.trim().slice(0, 100);
    if (q.length < 2) return { source: 'Deezer', items: [] };
    const rows = this.page(await this.deezer<DeezerPage<DeezerArtist>>(
      'search/artist', { q, limit: '15' }, 60_000,
    ));
    return {
      source: 'Deezer',
      items: rows.filter(row => Number.isSafeInteger(row.id) && !!row.name?.trim())
        .map(row => ({
          id: String(row.id),
          name: row.name,
          url: row.link ?? null,
          artworkUrl: row.picture_big ?? row.picture_medium ?? null,
        })),
    };
  }
}
