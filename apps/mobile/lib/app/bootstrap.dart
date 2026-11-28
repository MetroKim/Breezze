import 'dart:convert';
import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/api/breezze_api.dart';
import '../core/audio/playback_source_policy.dart';
import '../core/audio/remote_audio_grant.dart';
import 'download_preferences.dart';
import '../core/auth/auth_session.dart';
import '../core/database/database_providers.dart';
import '../core/database/db_instance.dart';
import '../core/database/favorites_dao.dart';
import '../features/player/player_controller.dart';

/// Composition root for Breezze app services.
///
/// Spotify/Deezer supply metadata discovery; neither public catalog API
/// grants native Breezze full-track streams. Official YouTube remains a
/// visible embedded video renderer. Local/rights-cleared streams use the
/// device audio engine; lyrics lookup is best-effort through LRCLIB.

/// package:http impl of the lyrics HTTP seam.
class HttpLyrics implements LyricsHttp {
  final http.Client _client = http.Client();

  @override
  Future<String> getText(String url) async {
    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw HttpException('lyrics_${response.statusCode}');
    }
    return response.body;
  }
}

/// Backend-backed federated catalog adapter. Search metadata comes from all
/// enabled providers; playback is still authorized separately by the API.
class BackendCatalogSourceAdapter implements ProviderAdapter {
  BackendCatalogSourceAdapter(this._ref);

  final Ref _ref;

  @override
  String get providerId => 'federated_catalog';

  @override
  String get adapterVersion => '1.0.0';

  ProviderTrack _trackFromJson(Map value, {String providerId = 'youtube_music'}) {
    final trackId = value['providerTrackId'] as String? ?? '';
    final duration = value['durationSec'];
    final isPreview = providerId == 'deezer' &&
        RegExp(r'^[0-9]{1,20}$').hasMatch(trackId) &&
        value['previewUrl'] is String &&
        (value['previewUrl'] as String).isNotEmpty;
    return ProviderTrack(
      // Deezer song identity stays stable when a preview is available;
      // previews are a separate explicit short-form action, never full songs.
      breezzeTrackId: 'bz:$providerId:$trackId',
      hasPreview: isPreview,
      providerTrackId: '$providerId:$trackId',
      title: value['title'] as String? ?? '',
      artist: value['artist'] as String? ?? 'Unknown artist',
      artworkUrl: value['artworkUrl'] as String?,
      duration: Duration(seconds: duration is num ? duration.toInt() : 0),
    );
  }

  // Legacy-API fallback only: the current server returns canonical grouped
  // entries under `tracks`. Never collapse covers, remixes, edits or songs
  // lacking duration evidence just because their titles look alike.
  bool _sameRecording(Map a, Map b) {
    String normalized(Object? text) =>
        text is String ? text.toLowerCase().trim()
            .replaceAll(RegExp(r'\s+'), ' ') : '';
    String? isrc(Object? value) {
      if (value is! String) return null;
      final code = value.toUpperCase().replaceAll(RegExp(r'[-\s]'), '');
      return RegExp(r'^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$').hasMatch(code)
          ? code : null;
    }
    final ia = isrc(a['isrc']);
    final ib = isrc(b['isrc']);
    if (ia != null && ib != null) return ia == ib;
    final ta = normalized(a['title']);
    final aa = normalized(a['artist']);
    if (ta.isEmpty || aa.isEmpty ||
        ta != normalized(b['title']) || aa != normalized(b['artist'])) {
      return false;
    }
    final da = a['durationSec'];
    final db = b['durationSec'];
    return da is num && db is num && da > 0 && db > 0 &&
        (da - db).abs() <= 3;
  }

  bool _validCatalogId(String name, String id) => switch (name) {
    'spotify' => RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id),
    'deezer' => RegExp(r'^[0-9]{1,20}$').hasMatch(id),
    'musicbrainz' => RegExp(
        r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}
  };

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) {
      return ProviderOk(<ProviderTrack>[]);
    }
    try {
      final api = _ref.read(authSessionProvider.notifier).api;
      // Rights-approved hosted audio is independently discoverable. A
      // Spotify/Deezer metadata outage must not conceal legitimately playable
      // recordings. Failed partner search is isolated from normal discovery.
      List<Map> authorized = [];
      try {
        final payload = await api.searchAuthorizedAudio(normalized);
        final raw = payload['items'];
        if (raw is List) authorized = raw.whereType<Map>().toList();
      } catch (_) {
        // The optional full-song catalog may not be provisioned yet.
      }
      Map<String, dynamic> response = {};
      try {
        response = await api.searchMusicCatalogs(normalized);
      } catch (_) {
        if (authorized.isEmpty) rethrow;
      }
      final shelves = response['providers'];
      final merged = response['tracks'];
      if (merged is! List && shelves is! List && authorized.isEmpty) {
        return ProviderError('invalid_music_catalog_response');
      }

      // The server owns source selection and returns one representative per
      // recording. Keep original provider IDs internally for metadata and
      // contractual attribution; they are never a user-facing source picker.
      final entries = <(String, Map)>[];
      if (merged is List) {
        for (final row in merged.whereType<Map>()) {
          final providerId = row['providerId'];
          if (providerId is String) entries.add((providerId, row));
        }
      } else if (shelves is List) {
        // Compatibility during rolling backend deployments.
        for (final name in const ['spotify', 'deezer', 'musicbrainz']) {
          for (final shelf in shelves.whereType<Map>()) {
            if (shelf['providerId'] != name) continue;
            final payload = shelf['result'];
            if (payload is! Map || payload['kind'] != 'ok' ||
                payload['value'] is! List) continue;
            for (final row in (payload['value'] as List).whereType<Map>()) {
              if (entries.any((existing) => _sameRecording(existing.$2, row))) {
                continue;
              }
              entries.add((name, row));
            }
          }
        }
      }

      // These rows are owned canonical tracks with current territory rights,
      // exact upstream ID and file availability checked by NestJS. Never
      // replace them with a metadata preview or a similarly named recording.
      for (final row in authorized.reversed) {
        final source = row['providerId'];
        final id = row['providerTrackId'];
        final canonical = row['canonicalTrackId'];
        if (source != 'opensubsonic' || id is! String ||
            !_validCatalogId('opensubsonic', id) ||
            canonical is! String ||
            !RegExp(r'^[a-fA-F0-9-]{36}
      for (final (name, row) in entries) {
        final id = row['providerTrackId'];
        if (id is! String || !_validCatalogId(name, id)) continue;
        final track = _trackFromJson(row, providerId: name);
        if (track.title.isNotEmpty && track.artist.isNotEmpty &&
            seen.add(track.breezzeTrackId)) {
          tracks.add(track);
        }
      }
      final hasValidSource = authorized.isNotEmpty || merged is List ||
          (shelves is List && shelves.whereType<Map>().any((shelf) {
            final result = shelf['result'];
            return result is Map && result['kind'] == 'ok';
          }));
      return hasValidSource
          ? ProviderOk(tracks)
          : ProviderError('music_catalogs_unavailable');
    } catch (_) {
      return ProviderError('music_catalog_network_error');
    }
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async {
    try {
      final separator = providerTrackId.indexOf(':');
      if (separator <= 0 || separator == providerTrackId.length - 1) {
        return ProviderError('invalid_provider_track_id');
      }
      final source = providerTrackId.substring(0, separator);
      final sourceTrackId = providerTrackId.substring(separator + 1);
      final data = await _ref.read(authSessionProvider.notifier).api
          .getProviderTrack(source, sourceTrackId);
      final value = data['value'];
      if (data['kind'] != 'ok' || value is! Map) {
        return ProviderError('track_metadata_unavailable');
      }
      return ProviderOk(_trackFromJson(value, providerId: source));
    } catch (_) {
      return ProviderError('network_error');
    }
  }

}

/// The app-wide metadata/search adapter; it is not a playback authority.
final catalogSourceProvider =
    Provider<ProviderAdapter>((ref) => BackendCatalogSourceAdapter(ref));

/// The lyrics provider.
final lyricsProvider =
    Provider<LyricsProvider>((ref) => LyricsProvider(HttpLyrics()));

/// Metadata search chain. No source in this chain grants playback rights.
final sourceChainProvider = Provider<SourceChain>((ref) => SourceChain([
      ref.watch(catalogSourceProvider),
    ]));

/// The playback resolver. Catalog metadata is converged to a canonical
/// backend track ID, then full-stream playback is authorized by the backend.
/// The mobile client never turns catalogue metadata directly into a
/// playable stream URL.
class LiveResolver implements PlaybackResolver {
  final Ref _ref;

  LiveResolver(this._ref);

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    // Explicit native Deezer PREVIEW only (30 seconds at most).
    // The authorized full Deezer recording remains inside Deezer's app.
    // External streaming services do not grant Breezze raw audio.
    if (isYouTubeSongId(track.id) ||
        track.id.startsWith('bz:spotify:') ||
        track.id.startsWith('bz:deezer:') ||
        isDeezerPreview(track.id) ||
        track.id.startsWith('bzv:')) {
      return null;
    }
    final auth = _ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return null;

    final api = _ref.read(authSessionProvider.notifier).api;
    if (api.accessToken == null) return null;

    if (isPublicAudioProofTrackId(track.id)) {
      const proofEnabled = bool.fromEnvironment(
        'BREEZZE_PUBLIC_AUDIO_PROOF',
        defaultValue: false,
      );
      if (!proofEnabled) return null;
      try {
        final grant = await api.audioProofPlayback();
        final url = grant['streamUrl'] as String?;
        final expiry = DateTime.tryParse(grant['expiresAt'] as String? ?? '');
        const expectedUrl =
            'https://upload.wikimedia.org/wikipedia/commons/transcoded/'
            '1/1f/Promise.ogg/Promise.ogg.mp3';
        if (grant['id'] != track.id ||
            grant['source'] != 'wikimedia_commons' ||
            grant['offlineAllowed'] != false ||
            url != expectedUrl ||
            expiry == null ||
            !isUsableRemoteAudioGrant(url!, expiry)) {
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: url,
          expiresAtUtc: expiry.toUtc(),
          codec: 'mp3',
        );
      } catch (_) {
        return null;
      }
    }

    // YouTube is VIDEO ONLY. Never resolve video metadata to native audio,
    // including previously matched local copies or device-side extraction.
    // The visible official YouTube player is opened by the UI coordinator.
    // Spotify tracks are also never raw media; official Spotify playback
    // is launched outside the Breezze audio engine via App Remote / deep link.

    try {
      final catalogId = await _resolveCatalogId(api, track);
      if (catalogId == null) return null;

      final providerIdentity = _providerIdentity(track.id);
      if (providerIdentity != null) {
        final session = await api.startPlaybackSession(
          providerId: providerIdentity.$1,
          providerTrackId: providerIdentity.$2,
          canonicalTrackId: catalogId,
        );
        final sessionId = session['id'] as String?;
        final playback = session['playback'];
        final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
        final expiresAt = playback is Map
            ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
            : null;
        if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
          if (sessionId != null) {
            try { await api.stopPlaybackSession(sessionId); } catch (_) {}
          }
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: streamUrl,
          expiresAtUtc: expiresAt.toUtc(),
          sessionId: sessionId,
          codec: playback['codec'] as String?,
        );
      }

      final preferences = await DownloadPreferencesStore().load();
      final session = await api.startPlaybackSession(
        trackId: catalogId,
        requestedQuality: preferences.streamingQuality,
      );
      final sessionId = session['id'] as String?;
      final playback = session['playback'];
      final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
      final expiresAt = playback is Map
          ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
          : null;
      if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
        if (sessionId != null) {
          try { await api.stopPlaybackSession(sessionId); } catch (_) {}
        }
        return null;
      }

      return PlayableSource(
        trackId: track.id,
        streamUrl: streamUrl,
        expiresAtUtc: expiresAt.toUtc(),
        sessionId: sessionId,
        codec: playback['codec'] as String?,
      );
    } catch (_) {
      // Rights denials and backend/network failures are unavailable playback,
      // not permission to fall back to an unlicensed provider URL.
      return null;
    }
  }

  (String, String)? _providerIdentity(String id) {
    if (!id.startsWith('bz:')) return null;
    final namespaced = id.substring(3);
    final separator = namespaced.indexOf(':');
    if (separator <= 0 || separator == namespaced.length - 1) return null;
    return (namespaced.substring(0, separator), namespaced.substring(separator + 1));
  }

  Future<String?> _resolveCatalogId(BreezzeApi api, TrackInfo track) async {
    if (!track.id.startsWith('bz:')) return track.id;

    final mapDao = _ref.read(catalogIdMapDaoProvider);
    final cached = await mapDao.lookup(track.id);
    if (cached != null) return cached;

    final title = track.title;
    final artist = track.artist;
    final provider = _providerIdentity(track.id);
    if (provider == null || title == null || title.trim().isEmpty ||
        artist == null || artist.trim().isEmpty) {
      return null;
    }

    final resolved = await api.resolveCatalogTrack(
      externalId: track.id,
      source: provider.$1,
      title: title,
      artistName: artist,
      durationSec: track.duration.inSeconds.clamp(1, 86400).toInt(),
    );
    final catalogId = resolved['id'] as String?;
    if (catalogId == null || catalogId.isEmpty) return null;
    await mapDao.save(track.id, catalogId);
    return catalogId;
  }
}

/// Resolver override applied in main() via ProviderScope.
final liveResolverProvider =
    Provider<PlaybackResolver>((ref) => LiveResolver(ref));

// ---------------------------------------------------------------------------
// Storage (path_provider): app-private, survives restarts
// ---------------------------------------------------------------------------

/// App-private downloads directory — the real per-track offline library.
Future<Directory> downloadsDirectory({required String userId}) async {
  // Scope local media by authenticated account. Never share one account's
  // downloaded catalogue with another account on the same device.
  final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (safeUserId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must be non-empty');
  }
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/downloads/$safeUserId');
  await dir.create(recursive: true);
  return dir;
}

// ---------------------------------------------------------------------------
// Favorites — drift-backed store, JSON kept only as the legacy import
// source for the one-shot migration.
// ---------------------------------------------------------------------------

/// A favorited track with its display info.
class FavoriteTrack {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;

  const FavoriteTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs = 0,
  });

  TrackInfo toTrackInfo() => TrackInfo(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: Duration(milliseconds: durationMs),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': durationMs,
      };

  static FavoriteTrack fromJson(Map<String, Object?> json) => FavoriteTrack(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String?,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}

/// Legacy JSON favorites reader — used ONLY by the one-shot migration.
class LegacyFavoritesJson {
  static const _fileName = 'breezze_favorites.json';

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/$_fileName');
  }

  Future<List<FavoriteTrack>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map) FavoriteTrack.fromJson(item.cast<String, Object?>())
      ];
    } catch (_) {
      return [];
    }
  }
}

/// Favorites store — drift-backed (SQLite). Same public API as the
/// JSON version (load / toggle / isFavorite), so screens are unchanged.
class FavoritesStore {
  final FavoritesDao _dao = FavoritesDao(breezzeDb);

  Future<List<FavoriteTrack>> load({String ownerId = 'guest'}) async {
    final rows = await _dao.list(ownerId: ownerId);
    return [
      for (final r in rows)
        FavoriteTrack(
          id: r.id.value,
          title: r.title.value,
          artist: r.artist.value,
          artworkUrl: r.artworkUrl.value,
          durationMs: r.durationMs.value,
        )
    ];
  }

  /// Returns true when the track was added, false when removed.
  Future<bool> toggle(
    FavoriteTrack track, {
    String ownerId = 'guest',
  }) async {
    if (await _dao.contains(track.id, ownerId: ownerId)) {
      await _dao.remove(track.id, ownerId: ownerId);
      return false;
    }
    await _dao.add(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: track.durationMs,
      ownerId: ownerId,
    );
    return true;
  }

  Future<bool> isFavorite(String id, {String ownerId = 'guest'}) =>
      _dao.contains(id, ownerId: ownerId);

  /// One-way hydration from a validated, account-scoped cloud snapshot.
  /// This does not produce local edits or upload the same rows again.
  Future<bool> reconcileCloud(
    String ownerId,
    List<FavoriteTrack> remote,
  ) => _dao.reconcileCloud(
        ownerId: ownerId,
        tracks: [
          for (final track in remote)
            (
              id: track.id,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              durationMs: track.durationMs,
            ),
        ],
      );
}

/// App-wide favorites store provider.
final favoritesStoreProvider =
    Provider<FavoritesStore>((ref) => FavoritesStore());

/// Read-only favorite state is scoped to both account and catalog track.
/// Album/follow providers use the same owner-aware invalidation convention.
typedef FavoriteTrackKey = ({String ownerId, String trackId});

final isTrackFavoriteProvider = FutureProvider.family<bool, FavoriteTrackKey>(
  (ref, key) => ref.read(favoritesStoreProvider)
      .isFavorite(key.trackId, ownerId: key.ownerId),
);

/// Invalidated after a saved-song mutation so the persistent Library tab
/// refreshes without requiring a route restart or another account sign-in.
final favoritesRefreshProvider = StateProvider<int>((ref) => 0);

      ).hasMatch(id),
    'opensubsonic' => RegExp(r'^[A-Za-z0-9_-]{1,128}
  };

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) {
      return ProviderOk(<ProviderTrack>[]);
    }
    try {
      final response = await _ref.read(authSessionProvider.notifier).api
          .searchMusicCatalogs(normalized);
      final shelves = response['providers'];
      final merged = response['tracks'];
      if (merged is! List && shelves is! List) {
        return ProviderError('invalid_music_catalog_response');
      }

      // The server owns source selection and returns one representative per
      // recording. Keep original provider IDs internally for metadata and
      // contractual attribution; they are never a user-facing source picker.
      final entries = <(String, Map)>[];
      if (merged is List) {
        for (final row in merged.whereType<Map>()) {
          final providerId = row['providerId'];
          if (providerId is String) entries.add((providerId, row));
        }
      } else if (shelves is List) {
        // Compatibility during rolling backend deployments.
        for (final name in const ['spotify', 'deezer', 'musicbrainz']) {
          for (final shelf in shelves.whereType<Map>()) {
            if (shelf['providerId'] != name) continue;
            final payload = shelf['result'];
            if (payload is! Map || payload['kind'] != 'ok' ||
                payload['value'] is! List) continue;
            for (final row in (payload['value'] as List).whereType<Map>()) {
              if (entries.any((existing) => _sameRecording(existing.$2, row))) {
                continue;
              }
              entries.add((name, row));
            }
          }
        }
      }

      final tracks = <ProviderTrack>[];
      final seen = <String>{};
      for (final (name, row) in entries) {
        final id = row['providerTrackId'];
        if (id is! String || !_validCatalogId(name, id)) continue;
        final track = _trackFromJson(row, providerId: name);
        if (track.title.isNotEmpty && track.artist.isNotEmpty &&
            seen.add(track.breezzeTrackId)) {
          tracks.add(track);
        }
      }
      final hasValidSource = merged is List ||
          (shelves is List && shelves.whereType<Map>().any((shelf) {
            final result = shelf['result'];
            return result is Map && result['kind'] == 'ok';
          }));
      return hasValidSource
          ? ProviderOk(tracks)
          : ProviderError('music_catalogs_unavailable');
    } catch (_) {
      return ProviderError('music_catalog_network_error');
    }
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async {
    try {
      final separator = providerTrackId.indexOf(':');
      if (separator <= 0 || separator == providerTrackId.length - 1) {
        return ProviderError('invalid_provider_track_id');
      }
      final source = providerTrackId.substring(0, separator);
      final sourceTrackId = providerTrackId.substring(separator + 1);
      final data = await _ref.read(authSessionProvider.notifier).api
          .getProviderTrack(source, sourceTrackId);
      final value = data['value'];
      if (data['kind'] != 'ok' || value is! Map) {
        return ProviderError('track_metadata_unavailable');
      }
      return ProviderOk(_trackFromJson(value, providerId: source));
    } catch (_) {
      return ProviderError('network_error');
    }
  }

}

/// The app-wide metadata/search adapter; it is not a playback authority.
final catalogSourceProvider =
    Provider<ProviderAdapter>((ref) => BackendCatalogSourceAdapter(ref));

/// The lyrics provider.
final lyricsProvider =
    Provider<LyricsProvider>((ref) => LyricsProvider(HttpLyrics()));

/// Metadata search chain. No source in this chain grants playback rights.
final sourceChainProvider = Provider<SourceChain>((ref) => SourceChain([
      ref.watch(catalogSourceProvider),
    ]));

/// The playback resolver. Catalog metadata is converged to a canonical
/// backend track ID, then full-stream playback is authorized by the backend.
/// The mobile client never turns catalogue metadata directly into a
/// playable stream URL.
class LiveResolver implements PlaybackResolver {
  final Ref _ref;

  LiveResolver(this._ref);

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    // Explicit native Deezer PREVIEW only (30 seconds at most).
    // The authorized full Deezer recording remains inside Deezer's app.
    // External streaming services do not grant Breezze raw audio.
    if (isYouTubeSongId(track.id) ||
        track.id.startsWith('bz:spotify:') ||
        track.id.startsWith('bz:deezer:') ||
        isDeezerPreview(track.id) ||
        track.id.startsWith('bzv:')) {
      return null;
    }
    final auth = _ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return null;

    final api = _ref.read(authSessionProvider.notifier).api;
    if (api.accessToken == null) return null;

    if (isPublicAudioProofTrackId(track.id)) {
      const proofEnabled = bool.fromEnvironment(
        'BREEZZE_PUBLIC_AUDIO_PROOF',
        defaultValue: false,
      );
      if (!proofEnabled) return null;
      try {
        final grant = await api.audioProofPlayback();
        final url = grant['streamUrl'] as String?;
        final expiry = DateTime.tryParse(grant['expiresAt'] as String? ?? '');
        const expectedUrl =
            'https://upload.wikimedia.org/wikipedia/commons/transcoded/'
            '1/1f/Promise.ogg/Promise.ogg.mp3';
        if (grant['id'] != track.id ||
            grant['source'] != 'wikimedia_commons' ||
            grant['offlineAllowed'] != false ||
            url != expectedUrl ||
            expiry == null ||
            !isUsableRemoteAudioGrant(url!, expiry)) {
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: url,
          expiresAtUtc: expiry.toUtc(),
          codec: 'mp3',
        );
      } catch (_) {
        return null;
      }
    }

    // YouTube is VIDEO ONLY. Never resolve video metadata to native audio,
    // including previously matched local copies or device-side extraction.
    // The visible official YouTube player is opened by the UI coordinator.
    // Spotify tracks are also never raw media; official Spotify playback
    // is launched outside the Breezze audio engine via App Remote / deep link.

    try {
      final catalogId = await _resolveCatalogId(api, track);
      if (catalogId == null) return null;

      final providerIdentity = _providerIdentity(track.id);
      if (providerIdentity != null) {
        final session = await api.startPlaybackSession(
          providerId: providerIdentity.$1,
          providerTrackId: providerIdentity.$2,
          canonicalTrackId: catalogId,
        );
        final sessionId = session['id'] as String?;
        final playback = session['playback'];
        final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
        final expiresAt = playback is Map
            ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
            : null;
        if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
          if (sessionId != null) {
            try { await api.stopPlaybackSession(sessionId); } catch (_) {}
          }
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: streamUrl,
          expiresAtUtc: expiresAt.toUtc(),
          sessionId: sessionId,
          codec: playback['codec'] as String?,
        );
      }

      final preferences = await DownloadPreferencesStore().load();
      final session = await api.startPlaybackSession(
        trackId: catalogId,
        requestedQuality: preferences.streamingQuality,
      );
      final sessionId = session['id'] as String?;
      final playback = session['playback'];
      final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
      final expiresAt = playback is Map
          ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
          : null;
      if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
        if (sessionId != null) {
          try { await api.stopPlaybackSession(sessionId); } catch (_) {}
        }
        return null;
      }

      return PlayableSource(
        trackId: track.id,
        streamUrl: streamUrl,
        expiresAtUtc: expiresAt.toUtc(),
        sessionId: sessionId,
        codec: playback['codec'] as String?,
      );
    } catch (_) {
      // Rights denials and backend/network failures are unavailable playback,
      // not permission to fall back to an unlicensed provider URL.
      return null;
    }
  }

  (String, String)? _providerIdentity(String id) {
    if (!id.startsWith('bz:')) return null;
    final namespaced = id.substring(3);
    final separator = namespaced.indexOf(':');
    if (separator <= 0 || separator == namespaced.length - 1) return null;
    return (namespaced.substring(0, separator), namespaced.substring(separator + 1));
  }

  Future<String?> _resolveCatalogId(BreezzeApi api, TrackInfo track) async {
    if (!track.id.startsWith('bz:')) return track.id;

    final mapDao = _ref.read(catalogIdMapDaoProvider);
    final cached = await mapDao.lookup(track.id);
    if (cached != null) return cached;

    final title = track.title;
    final artist = track.artist;
    final provider = _providerIdentity(track.id);
    if (provider == null || title == null || title.trim().isEmpty ||
        artist == null || artist.trim().isEmpty) {
      return null;
    }

    final resolved = await api.resolveCatalogTrack(
      externalId: track.id,
      source: provider.$1,
      title: title,
      artistName: artist,
      durationSec: track.duration.inSeconds.clamp(1, 86400).toInt(),
    );
    final catalogId = resolved['id'] as String?;
    if (catalogId == null || catalogId.isEmpty) return null;
    await mapDao.save(track.id, catalogId);
    return catalogId;
  }
}

/// Resolver override applied in main() via ProviderScope.
final liveResolverProvider =
    Provider<PlaybackResolver>((ref) => LiveResolver(ref));

// ---------------------------------------------------------------------------
// Storage (path_provider): app-private, survives restarts
// ---------------------------------------------------------------------------

/// App-private downloads directory — the real per-track offline library.
Future<Directory> downloadsDirectory({required String userId}) async {
  // Scope local media by authenticated account. Never share one account's
  // downloaded catalogue with another account on the same device.
  final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (safeUserId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must be non-empty');
  }
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/downloads/$safeUserId');
  await dir.create(recursive: true);
  return dir;
}

// ---------------------------------------------------------------------------
// Favorites — drift-backed store, JSON kept only as the legacy import
// source for the one-shot migration.
// ---------------------------------------------------------------------------

/// A favorited track with its display info.
class FavoriteTrack {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;

  const FavoriteTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs = 0,
  });

  TrackInfo toTrackInfo() => TrackInfo(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: Duration(milliseconds: durationMs),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': durationMs,
      };

  static FavoriteTrack fromJson(Map<String, Object?> json) => FavoriteTrack(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String?,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}

/// Legacy JSON favorites reader — used ONLY by the one-shot migration.
class LegacyFavoritesJson {
  static const _fileName = 'breezze_favorites.json';

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/$_fileName');
  }

  Future<List<FavoriteTrack>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map) FavoriteTrack.fromJson(item.cast<String, Object?>())
      ];
    } catch (_) {
      return [];
    }
  }
}

/// Favorites store — drift-backed (SQLite). Same public API as the
/// JSON version (load / toggle / isFavorite), so screens are unchanged.
class FavoritesStore {
  final FavoritesDao _dao = FavoritesDao(breezzeDb);

  Future<List<FavoriteTrack>> load({String ownerId = 'guest'}) async {
    final rows = await _dao.list(ownerId: ownerId);
    return [
      for (final r in rows)
        FavoriteTrack(
          id: r.id.value,
          title: r.title.value,
          artist: r.artist.value,
          artworkUrl: r.artworkUrl.value,
          durationMs: r.durationMs.value,
        )
    ];
  }

  /// Returns true when the track was added, false when removed.
  Future<bool> toggle(
    FavoriteTrack track, {
    String ownerId = 'guest',
  }) async {
    if (await _dao.contains(track.id, ownerId: ownerId)) {
      await _dao.remove(track.id, ownerId: ownerId);
      return false;
    }
    await _dao.add(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: track.durationMs,
      ownerId: ownerId,
    );
    return true;
  }

  Future<bool> isFavorite(String id, {String ownerId = 'guest'}) =>
      _dao.contains(id, ownerId: ownerId);

  /// One-way hydration from a validated, account-scoped cloud snapshot.
  /// This does not produce local edits or upload the same rows again.
  Future<bool> reconcileCloud(
    String ownerId,
    List<FavoriteTrack> remote,
  ) => _dao.reconcileCloud(
        ownerId: ownerId,
        tracks: [
          for (final track in remote)
            (
              id: track.id,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              durationMs: track.durationMs,
            ),
        ],
      );
}

/// App-wide favorites store provider.
final favoritesStoreProvider =
    Provider<FavoritesStore>((ref) => FavoritesStore());

/// Read-only favorite state is scoped to both account and catalog track.
/// Album/follow providers use the same owner-aware invalidation convention.
typedef FavoriteTrackKey = ({String ownerId, String trackId});

final isTrackFavoriteProvider = FutureProvider.family<bool, FavoriteTrackKey>(
  (ref, key) => ref.read(favoritesStoreProvider)
      .isFavorite(key.trackId, ownerId: key.ownerId),
);

/// Invalidated after a saved-song mutation so the persistent Library tab
/// refreshes without requiring a route restart or another account sign-in.
final favoritesRefreshProvider = StateProvider<int>((ref) => 0);
).hasMatch(id),
    _ => false,
  };

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) {
      return ProviderOk(<ProviderTrack>[]);
    }
    try {
      final response = await _ref.read(authSessionProvider.notifier).api
          .searchMusicCatalogs(normalized);
      final shelves = response['providers'];
      final merged = response['tracks'];
      if (merged is! List && shelves is! List) {
        return ProviderError('invalid_music_catalog_response');
      }

      // The server owns source selection and returns one representative per
      // recording. Keep original provider IDs internally for metadata and
      // contractual attribution; they are never a user-facing source picker.
      final entries = <(String, Map)>[];
      if (merged is List) {
        for (final row in merged.whereType<Map>()) {
          final providerId = row['providerId'];
          if (providerId is String) entries.add((providerId, row));
        }
      } else if (shelves is List) {
        // Compatibility during rolling backend deployments.
        for (final name in const ['spotify', 'deezer', 'musicbrainz']) {
          for (final shelf in shelves.whereType<Map>()) {
            if (shelf['providerId'] != name) continue;
            final payload = shelf['result'];
            if (payload is! Map || payload['kind'] != 'ok' ||
                payload['value'] is! List) continue;
            for (final row in (payload['value'] as List).whereType<Map>()) {
              if (entries.any((existing) => _sameRecording(existing.$2, row))) {
                continue;
              }
              entries.add((name, row));
            }
          }
        }
      }

      final tracks = <ProviderTrack>[];
      final seen = <String>{};
      for (final (name, row) in entries) {
        final id = row['providerTrackId'];
        if (id is! String || !_validCatalogId(name, id)) continue;
        final track = _trackFromJson(row, providerId: name);
        if (track.title.isNotEmpty && track.artist.isNotEmpty &&
            seen.add(track.breezzeTrackId)) {
          tracks.add(track);
        }
      }
      final hasValidSource = merged is List ||
          (shelves is List && shelves.whereType<Map>().any((shelf) {
            final result = shelf['result'];
            return result is Map && result['kind'] == 'ok';
          }));
      return hasValidSource
          ? ProviderOk(tracks)
          : ProviderError('music_catalogs_unavailable');
    } catch (_) {
      return ProviderError('music_catalog_network_error');
    }
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async {
    try {
      final separator = providerTrackId.indexOf(':');
      if (separator <= 0 || separator == providerTrackId.length - 1) {
        return ProviderError('invalid_provider_track_id');
      }
      final source = providerTrackId.substring(0, separator);
      final sourceTrackId = providerTrackId.substring(separator + 1);
      final data = await _ref.read(authSessionProvider.notifier).api
          .getProviderTrack(source, sourceTrackId);
      final value = data['value'];
      if (data['kind'] != 'ok' || value is! Map) {
        return ProviderError('track_metadata_unavailable');
      }
      return ProviderOk(_trackFromJson(value, providerId: source));
    } catch (_) {
      return ProviderError('network_error');
    }
  }

}

/// The app-wide metadata/search adapter; it is not a playback authority.
final catalogSourceProvider =
    Provider<ProviderAdapter>((ref) => BackendCatalogSourceAdapter(ref));

/// The lyrics provider.
final lyricsProvider =
    Provider<LyricsProvider>((ref) => LyricsProvider(HttpLyrics()));

/// Metadata search chain. No source in this chain grants playback rights.
final sourceChainProvider = Provider<SourceChain>((ref) => SourceChain([
      ref.watch(catalogSourceProvider),
    ]));

/// The playback resolver. Catalog metadata is converged to a canonical
/// backend track ID, then full-stream playback is authorized by the backend.
/// The mobile client never turns catalogue metadata directly into a
/// playable stream URL.
class LiveResolver implements PlaybackResolver {
  final Ref _ref;

  LiveResolver(this._ref);

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    // Explicit native Deezer PREVIEW only (30 seconds at most).
    // The authorized full Deezer recording remains inside Deezer's app.
    // External streaming services do not grant Breezze raw audio.
    if (isYouTubeSongId(track.id) ||
        track.id.startsWith('bz:spotify:') ||
        track.id.startsWith('bz:deezer:') ||
        isDeezerPreview(track.id) ||
        track.id.startsWith('bzv:')) {
      return null;
    }
    final auth = _ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return null;

    final api = _ref.read(authSessionProvider.notifier).api;
    if (api.accessToken == null) return null;

    if (isPublicAudioProofTrackId(track.id)) {
      const proofEnabled = bool.fromEnvironment(
        'BREEZZE_PUBLIC_AUDIO_PROOF',
        defaultValue: false,
      );
      if (!proofEnabled) return null;
      try {
        final grant = await api.audioProofPlayback();
        final url = grant['streamUrl'] as String?;
        final expiry = DateTime.tryParse(grant['expiresAt'] as String? ?? '');
        const expectedUrl =
            'https://upload.wikimedia.org/wikipedia/commons/transcoded/'
            '1/1f/Promise.ogg/Promise.ogg.mp3';
        if (grant['id'] != track.id ||
            grant['source'] != 'wikimedia_commons' ||
            grant['offlineAllowed'] != false ||
            url != expectedUrl ||
            expiry == null ||
            !isUsableRemoteAudioGrant(url!, expiry)) {
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: url,
          expiresAtUtc: expiry.toUtc(),
          codec: 'mp3',
        );
      } catch (_) {
        return null;
      }
    }

    // YouTube is VIDEO ONLY. Never resolve video metadata to native audio,
    // including previously matched local copies or device-side extraction.
    // The visible official YouTube player is opened by the UI coordinator.
    // Spotify tracks are also never raw media; official Spotify playback
    // is launched outside the Breezze audio engine via App Remote / deep link.

    try {
      final catalogId = await _resolveCatalogId(api, track);
      if (catalogId == null) return null;

      final providerIdentity = _providerIdentity(track.id);
      if (providerIdentity != null) {
        final session = await api.startPlaybackSession(
          providerId: providerIdentity.$1,
          providerTrackId: providerIdentity.$2,
          canonicalTrackId: catalogId,
        );
        final sessionId = session['id'] as String?;
        final playback = session['playback'];
        final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
        final expiresAt = playback is Map
            ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
            : null;
        if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
          if (sessionId != null) {
            try { await api.stopPlaybackSession(sessionId); } catch (_) {}
          }
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: streamUrl,
          expiresAtUtc: expiresAt.toUtc(),
          sessionId: sessionId,
          codec: playback['codec'] as String?,
        );
      }

      final preferences = await DownloadPreferencesStore().load();
      final session = await api.startPlaybackSession(
        trackId: catalogId,
        requestedQuality: preferences.streamingQuality,
      );
      final sessionId = session['id'] as String?;
      final playback = session['playback'];
      final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
      final expiresAt = playback is Map
          ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
          : null;
      if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
        if (sessionId != null) {
          try { await api.stopPlaybackSession(sessionId); } catch (_) {}
        }
        return null;
      }

      return PlayableSource(
        trackId: track.id,
        streamUrl: streamUrl,
        expiresAtUtc: expiresAt.toUtc(),
        sessionId: sessionId,
        codec: playback['codec'] as String?,
      );
    } catch (_) {
      // Rights denials and backend/network failures are unavailable playback,
      // not permission to fall back to an unlicensed provider URL.
      return null;
    }
  }

  (String, String)? _providerIdentity(String id) {
    if (!id.startsWith('bz:')) return null;
    final namespaced = id.substring(3);
    final separator = namespaced.indexOf(':');
    if (separator <= 0 || separator == namespaced.length - 1) return null;
    return (namespaced.substring(0, separator), namespaced.substring(separator + 1));
  }

  Future<String?> _resolveCatalogId(BreezzeApi api, TrackInfo track) async {
    if (!track.id.startsWith('bz:')) return track.id;

    final mapDao = _ref.read(catalogIdMapDaoProvider);
    final cached = await mapDao.lookup(track.id);
    if (cached != null) return cached;

    final title = track.title;
    final artist = track.artist;
    final provider = _providerIdentity(track.id);
    if (provider == null || title == null || title.trim().isEmpty ||
        artist == null || artist.trim().isEmpty) {
      return null;
    }

    final resolved = await api.resolveCatalogTrack(
      externalId: track.id,
      source: provider.$1,
      title: title,
      artistName: artist,
      durationSec: track.duration.inSeconds.clamp(1, 86400).toInt(),
    );
    final catalogId = resolved['id'] as String?;
    if (catalogId == null || catalogId.isEmpty) return null;
    await mapDao.save(track.id, catalogId);
    return catalogId;
  }
}

/// Resolver override applied in main() via ProviderScope.
final liveResolverProvider =
    Provider<PlaybackResolver>((ref) => LiveResolver(ref));

// ---------------------------------------------------------------------------
// Storage (path_provider): app-private, survives restarts
// ---------------------------------------------------------------------------

/// App-private downloads directory — the real per-track offline library.
Future<Directory> downloadsDirectory({required String userId}) async {
  // Scope local media by authenticated account. Never share one account's
  // downloaded catalogue with another account on the same device.
  final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (safeUserId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must be non-empty');
  }
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/downloads/$safeUserId');
  await dir.create(recursive: true);
  return dir;
}

// ---------------------------------------------------------------------------
// Favorites — drift-backed store, JSON kept only as the legacy import
// source for the one-shot migration.
// ---------------------------------------------------------------------------

/// A favorited track with its display info.
class FavoriteTrack {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;

  const FavoriteTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs = 0,
  });

  TrackInfo toTrackInfo() => TrackInfo(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: Duration(milliseconds: durationMs),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': durationMs,
      };

  static FavoriteTrack fromJson(Map<String, Object?> json) => FavoriteTrack(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String?,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}

/// Legacy JSON favorites reader — used ONLY by the one-shot migration.
class LegacyFavoritesJson {
  static const _fileName = 'breezze_favorites.json';

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/$_fileName');
  }

  Future<List<FavoriteTrack>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map) FavoriteTrack.fromJson(item.cast<String, Object?>())
      ];
    } catch (_) {
      return [];
    }
  }
}

/// Favorites store — drift-backed (SQLite). Same public API as the
/// JSON version (load / toggle / isFavorite), so screens are unchanged.
class FavoritesStore {
  final FavoritesDao _dao = FavoritesDao(breezzeDb);

  Future<List<FavoriteTrack>> load({String ownerId = 'guest'}) async {
    final rows = await _dao.list(ownerId: ownerId);
    return [
      for (final r in rows)
        FavoriteTrack(
          id: r.id.value,
          title: r.title.value,
          artist: r.artist.value,
          artworkUrl: r.artworkUrl.value,
          durationMs: r.durationMs.value,
        )
    ];
  }

  /// Returns true when the track was added, false when removed.
  Future<bool> toggle(
    FavoriteTrack track, {
    String ownerId = 'guest',
  }) async {
    if (await _dao.contains(track.id, ownerId: ownerId)) {
      await _dao.remove(track.id, ownerId: ownerId);
      return false;
    }
    await _dao.add(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: track.durationMs,
      ownerId: ownerId,
    );
    return true;
  }

  Future<bool> isFavorite(String id, {String ownerId = 'guest'}) =>
      _dao.contains(id, ownerId: ownerId);

  /// One-way hydration from a validated, account-scoped cloud snapshot.
  /// This does not produce local edits or upload the same rows again.
  Future<bool> reconcileCloud(
    String ownerId,
    List<FavoriteTrack> remote,
  ) => _dao.reconcileCloud(
        ownerId: ownerId,
        tracks: [
          for (final track in remote)
            (
              id: track.id,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              durationMs: track.durationMs,
            ),
        ],
      );
}

/// App-wide favorites store provider.
final favoritesStoreProvider =
    Provider<FavoritesStore>((ref) => FavoritesStore());

/// Read-only favorite state is scoped to both account and catalog track.
/// Album/follow providers use the same owner-aware invalidation convention.
typedef FavoriteTrackKey = ({String ownerId, String trackId});

final isTrackFavoriteProvider = FutureProvider.family<bool, FavoriteTrackKey>(
  (ref, key) => ref.read(favoritesStoreProvider)
      .isFavorite(key.trackId, ownerId: key.ownerId),
);

/// Invalidated after a saved-song mutation so the persistent Library tab
/// refreshes without requiring a route restart or another account sign-in.
final favoritesRefreshProvider = StateProvider<int>((ref) => 0);
).hasMatch(canonical) ||
            row['title'] is! String || row['artist'] is! String ||
            (row['title'] as String).trim().isEmpty ||
            (row['artist'] as String).trim().isEmpty) continue;
        entries.insert(0, ('opensubsonic', row));
      }

      final tracks = <ProviderTrack>[];
      final seen = <String>{};
      for (final (name, row) in entries) {
        final id = row['providerTrackId'];
        if (id is! String || !_validCatalogId(name, id)) continue;
        final track = _trackFromJson(row, providerId: name);
        if (track.title.isNotEmpty && track.artist.isNotEmpty &&
            seen.add(track.breezzeTrackId)) {
          tracks.add(track);
        }
      }
      final hasValidSource = merged is List ||
          (shelves is List && shelves.whereType<Map>().any((shelf) {
            final result = shelf['result'];
            return result is Map && result['kind'] == 'ok';
          }));
      return hasValidSource
          ? ProviderOk(tracks)
          : ProviderError('music_catalogs_unavailable');
    } catch (_) {
      return ProviderError('music_catalog_network_error');
    }
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async {
    try {
      final separator = providerTrackId.indexOf(':');
      if (separator <= 0 || separator == providerTrackId.length - 1) {
        return ProviderError('invalid_provider_track_id');
      }
      final source = providerTrackId.substring(0, separator);
      final sourceTrackId = providerTrackId.substring(separator + 1);
      final data = await _ref.read(authSessionProvider.notifier).api
          .getProviderTrack(source, sourceTrackId);
      final value = data['value'];
      if (data['kind'] != 'ok' || value is! Map) {
        return ProviderError('track_metadata_unavailable');
      }
      return ProviderOk(_trackFromJson(value, providerId: source));
    } catch (_) {
      return ProviderError('network_error');
    }
  }

}

/// The app-wide metadata/search adapter; it is not a playback authority.
final catalogSourceProvider =
    Provider<ProviderAdapter>((ref) => BackendCatalogSourceAdapter(ref));

/// The lyrics provider.
final lyricsProvider =
    Provider<LyricsProvider>((ref) => LyricsProvider(HttpLyrics()));

/// Metadata search chain. No source in this chain grants playback rights.
final sourceChainProvider = Provider<SourceChain>((ref) => SourceChain([
      ref.watch(catalogSourceProvider),
    ]));

/// The playback resolver. Catalog metadata is converged to a canonical
/// backend track ID, then full-stream playback is authorized by the backend.
/// The mobile client never turns catalogue metadata directly into a
/// playable stream URL.
class LiveResolver implements PlaybackResolver {
  final Ref _ref;

  LiveResolver(this._ref);

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    // Explicit native Deezer PREVIEW only (30 seconds at most).
    // The authorized full Deezer recording remains inside Deezer's app.
    // External streaming services do not grant Breezze raw audio.
    if (isYouTubeSongId(track.id) ||
        track.id.startsWith('bz:spotify:') ||
        track.id.startsWith('bz:deezer:') ||
        isDeezerPreview(track.id) ||
        track.id.startsWith('bzv:')) {
      return null;
    }
    final auth = _ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return null;

    final api = _ref.read(authSessionProvider.notifier).api;
    if (api.accessToken == null) return null;

    if (isPublicAudioProofTrackId(track.id)) {
      const proofEnabled = bool.fromEnvironment(
        'BREEZZE_PUBLIC_AUDIO_PROOF',
        defaultValue: false,
      );
      if (!proofEnabled) return null;
      try {
        final grant = await api.audioProofPlayback();
        final url = grant['streamUrl'] as String?;
        final expiry = DateTime.tryParse(grant['expiresAt'] as String? ?? '');
        const expectedUrl =
            'https://upload.wikimedia.org/wikipedia/commons/transcoded/'
            '1/1f/Promise.ogg/Promise.ogg.mp3';
        if (grant['id'] != track.id ||
            grant['source'] != 'wikimedia_commons' ||
            grant['offlineAllowed'] != false ||
            url != expectedUrl ||
            expiry == null ||
            !isUsableRemoteAudioGrant(url!, expiry)) {
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: url,
          expiresAtUtc: expiry.toUtc(),
          codec: 'mp3',
        );
      } catch (_) {
        return null;
      }
    }

    // YouTube is VIDEO ONLY. Never resolve video metadata to native audio,
    // including previously matched local copies or device-side extraction.
    // The visible official YouTube player is opened by the UI coordinator.
    // Spotify tracks are also never raw media; official Spotify playback
    // is launched outside the Breezze audio engine via App Remote / deep link.

    try {
      final catalogId = await _resolveCatalogId(api, track);
      if (catalogId == null) return null;

      final providerIdentity = _providerIdentity(track.id);
      if (providerIdentity != null) {
        final session = await api.startPlaybackSession(
          providerId: providerIdentity.$1,
          providerTrackId: providerIdentity.$2,
          canonicalTrackId: catalogId,
        );
        final sessionId = session['id'] as String?;
        final playback = session['playback'];
        final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
        final expiresAt = playback is Map
            ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
            : null;
        if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
          if (sessionId != null) {
            try { await api.stopPlaybackSession(sessionId); } catch (_) {}
          }
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: streamUrl,
          expiresAtUtc: expiresAt.toUtc(),
          sessionId: sessionId,
          codec: playback['codec'] as String?,
        );
      }

      final preferences = await DownloadPreferencesStore().load();
      final session = await api.startPlaybackSession(
        trackId: catalogId,
        requestedQuality: preferences.streamingQuality,
      );
      final sessionId = session['id'] as String?;
      final playback = session['playback'];
      final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
      final expiresAt = playback is Map
          ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
          : null;
      if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
        if (sessionId != null) {
          try { await api.stopPlaybackSession(sessionId); } catch (_) {}
        }
        return null;
      }

      return PlayableSource(
        trackId: track.id,
        streamUrl: streamUrl,
        expiresAtUtc: expiresAt.toUtc(),
        sessionId: sessionId,
        codec: playback['codec'] as String?,
      );
    } catch (_) {
      // Rights denials and backend/network failures are unavailable playback,
      // not permission to fall back to an unlicensed provider URL.
      return null;
    }
  }

  (String, String)? _providerIdentity(String id) {
    if (!id.startsWith('bz:')) return null;
    final namespaced = id.substring(3);
    final separator = namespaced.indexOf(':');
    if (separator <= 0 || separator == namespaced.length - 1) return null;
    return (namespaced.substring(0, separator), namespaced.substring(separator + 1));
  }

  Future<String?> _resolveCatalogId(BreezzeApi api, TrackInfo track) async {
    if (!track.id.startsWith('bz:')) return track.id;

    final mapDao = _ref.read(catalogIdMapDaoProvider);
    final cached = await mapDao.lookup(track.id);
    if (cached != null) return cached;

    final title = track.title;
    final artist = track.artist;
    final provider = _providerIdentity(track.id);
    if (provider == null || title == null || title.trim().isEmpty ||
        artist == null || artist.trim().isEmpty) {
      return null;
    }

    final resolved = await api.resolveCatalogTrack(
      externalId: track.id,
      source: provider.$1,
      title: title,
      artistName: artist,
      durationSec: track.duration.inSeconds.clamp(1, 86400).toInt(),
    );
    final catalogId = resolved['id'] as String?;
    if (catalogId == null || catalogId.isEmpty) return null;
    await mapDao.save(track.id, catalogId);
    return catalogId;
  }
}

/// Resolver override applied in main() via ProviderScope.
final liveResolverProvider =
    Provider<PlaybackResolver>((ref) => LiveResolver(ref));

// ---------------------------------------------------------------------------
// Storage (path_provider): app-private, survives restarts
// ---------------------------------------------------------------------------

/// App-private downloads directory — the real per-track offline library.
Future<Directory> downloadsDirectory({required String userId}) async {
  // Scope local media by authenticated account. Never share one account's
  // downloaded catalogue with another account on the same device.
  final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (safeUserId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must be non-empty');
  }
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/downloads/$safeUserId');
  await dir.create(recursive: true);
  return dir;
}

// ---------------------------------------------------------------------------
// Favorites — drift-backed store, JSON kept only as the legacy import
// source for the one-shot migration.
// ---------------------------------------------------------------------------

/// A favorited track with its display info.
class FavoriteTrack {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;

  const FavoriteTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs = 0,
  });

  TrackInfo toTrackInfo() => TrackInfo(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: Duration(milliseconds: durationMs),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': durationMs,
      };

  static FavoriteTrack fromJson(Map<String, Object?> json) => FavoriteTrack(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String?,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}

/// Legacy JSON favorites reader — used ONLY by the one-shot migration.
class LegacyFavoritesJson {
  static const _fileName = 'breezze_favorites.json';

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/$_fileName');
  }

  Future<List<FavoriteTrack>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map) FavoriteTrack.fromJson(item.cast<String, Object?>())
      ];
    } catch (_) {
      return [];
    }
  }
}

/// Favorites store — drift-backed (SQLite). Same public API as the
/// JSON version (load / toggle / isFavorite), so screens are unchanged.
class FavoritesStore {
  final FavoritesDao _dao = FavoritesDao(breezzeDb);

  Future<List<FavoriteTrack>> load({String ownerId = 'guest'}) async {
    final rows = await _dao.list(ownerId: ownerId);
    return [
      for (final r in rows)
        FavoriteTrack(
          id: r.id.value,
          title: r.title.value,
          artist: r.artist.value,
          artworkUrl: r.artworkUrl.value,
          durationMs: r.durationMs.value,
        )
    ];
  }

  /// Returns true when the track was added, false when removed.
  Future<bool> toggle(
    FavoriteTrack track, {
    String ownerId = 'guest',
  }) async {
    if (await _dao.contains(track.id, ownerId: ownerId)) {
      await _dao.remove(track.id, ownerId: ownerId);
      return false;
    }
    await _dao.add(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: track.durationMs,
      ownerId: ownerId,
    );
    return true;
  }

  Future<bool> isFavorite(String id, {String ownerId = 'guest'}) =>
      _dao.contains(id, ownerId: ownerId);

  /// One-way hydration from a validated, account-scoped cloud snapshot.
  /// This does not produce local edits or upload the same rows again.
  Future<bool> reconcileCloud(
    String ownerId,
    List<FavoriteTrack> remote,
  ) => _dao.reconcileCloud(
        ownerId: ownerId,
        tracks: [
          for (final track in remote)
            (
              id: track.id,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              durationMs: track.durationMs,
            ),
        ],
      );
}

/// App-wide favorites store provider.
final favoritesStoreProvider =
    Provider<FavoritesStore>((ref) => FavoritesStore());

/// Read-only favorite state is scoped to both account and catalog track.
/// Album/follow providers use the same owner-aware invalidation convention.
typedef FavoriteTrackKey = ({String ownerId, String trackId});

final isTrackFavoriteProvider = FutureProvider.family<bool, FavoriteTrackKey>(
  (ref, key) => ref.read(favoritesStoreProvider)
      .isFavorite(key.trackId, ownerId: key.ownerId),
);

/// Invalidated after a saved-song mutation so the persistent Library tab
/// refreshes without requiring a route restart or another account sign-in.
final favoritesRefreshProvider = StateProvider<int>((ref) => 0);

      ).hasMatch(id),
    'opensubsonic' => RegExp(r'^[A-Za-z0-9_-]{1,128}
  };

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) {
      return ProviderOk(<ProviderTrack>[]);
    }
    try {
      final response = await _ref.read(authSessionProvider.notifier).api
          .searchMusicCatalogs(normalized);
      final shelves = response['providers'];
      final merged = response['tracks'];
      if (merged is! List && shelves is! List) {
        return ProviderError('invalid_music_catalog_response');
      }

      // The server owns source selection and returns one representative per
      // recording. Keep original provider IDs internally for metadata and
      // contractual attribution; they are never a user-facing source picker.
      final entries = <(String, Map)>[];
      if (merged is List) {
        for (final row in merged.whereType<Map>()) {
          final providerId = row['providerId'];
          if (providerId is String) entries.add((providerId, row));
        }
      } else if (shelves is List) {
        // Compatibility during rolling backend deployments.
        for (final name in const ['spotify', 'deezer', 'musicbrainz']) {
          for (final shelf in shelves.whereType<Map>()) {
            if (shelf['providerId'] != name) continue;
            final payload = shelf['result'];
            if (payload is! Map || payload['kind'] != 'ok' ||
                payload['value'] is! List) continue;
            for (final row in (payload['value'] as List).whereType<Map>()) {
              if (entries.any((existing) => _sameRecording(existing.$2, row))) {
                continue;
              }
              entries.add((name, row));
            }
          }
        }
      }

      final tracks = <ProviderTrack>[];
      final seen = <String>{};
      for (final (name, row) in entries) {
        final id = row['providerTrackId'];
        if (id is! String || !_validCatalogId(name, id)) continue;
        final track = _trackFromJson(row, providerId: name);
        if (track.title.isNotEmpty && track.artist.isNotEmpty &&
            seen.add(track.breezzeTrackId)) {
          tracks.add(track);
        }
      }
      final hasValidSource = merged is List ||
          (shelves is List && shelves.whereType<Map>().any((shelf) {
            final result = shelf['result'];
            return result is Map && result['kind'] == 'ok';
          }));
      return hasValidSource
          ? ProviderOk(tracks)
          : ProviderError('music_catalogs_unavailable');
    } catch (_) {
      return ProviderError('music_catalog_network_error');
    }
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async {
    try {
      final separator = providerTrackId.indexOf(':');
      if (separator <= 0 || separator == providerTrackId.length - 1) {
        return ProviderError('invalid_provider_track_id');
      }
      final source = providerTrackId.substring(0, separator);
      final sourceTrackId = providerTrackId.substring(separator + 1);
      final data = await _ref.read(authSessionProvider.notifier).api
          .getProviderTrack(source, sourceTrackId);
      final value = data['value'];
      if (data['kind'] != 'ok' || value is! Map) {
        return ProviderError('track_metadata_unavailable');
      }
      return ProviderOk(_trackFromJson(value, providerId: source));
    } catch (_) {
      return ProviderError('network_error');
    }
  }

}

/// The app-wide metadata/search adapter; it is not a playback authority.
final catalogSourceProvider =
    Provider<ProviderAdapter>((ref) => BackendCatalogSourceAdapter(ref));

/// The lyrics provider.
final lyricsProvider =
    Provider<LyricsProvider>((ref) => LyricsProvider(HttpLyrics()));

/// Metadata search chain. No source in this chain grants playback rights.
final sourceChainProvider = Provider<SourceChain>((ref) => SourceChain([
      ref.watch(catalogSourceProvider),
    ]));

/// The playback resolver. Catalog metadata is converged to a canonical
/// backend track ID, then full-stream playback is authorized by the backend.
/// The mobile client never turns catalogue metadata directly into a
/// playable stream URL.
class LiveResolver implements PlaybackResolver {
  final Ref _ref;

  LiveResolver(this._ref);

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    // Explicit native Deezer PREVIEW only (30 seconds at most).
    // The authorized full Deezer recording remains inside Deezer's app.
    // External streaming services do not grant Breezze raw audio.
    if (isYouTubeSongId(track.id) ||
        track.id.startsWith('bz:spotify:') ||
        track.id.startsWith('bz:deezer:') ||
        isDeezerPreview(track.id) ||
        track.id.startsWith('bzv:')) {
      return null;
    }
    final auth = _ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return null;

    final api = _ref.read(authSessionProvider.notifier).api;
    if (api.accessToken == null) return null;

    if (isPublicAudioProofTrackId(track.id)) {
      const proofEnabled = bool.fromEnvironment(
        'BREEZZE_PUBLIC_AUDIO_PROOF',
        defaultValue: false,
      );
      if (!proofEnabled) return null;
      try {
        final grant = await api.audioProofPlayback();
        final url = grant['streamUrl'] as String?;
        final expiry = DateTime.tryParse(grant['expiresAt'] as String? ?? '');
        const expectedUrl =
            'https://upload.wikimedia.org/wikipedia/commons/transcoded/'
            '1/1f/Promise.ogg/Promise.ogg.mp3';
        if (grant['id'] != track.id ||
            grant['source'] != 'wikimedia_commons' ||
            grant['offlineAllowed'] != false ||
            url != expectedUrl ||
            expiry == null ||
            !isUsableRemoteAudioGrant(url!, expiry)) {
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: url,
          expiresAtUtc: expiry.toUtc(),
          codec: 'mp3',
        );
      } catch (_) {
        return null;
      }
    }

    // YouTube is VIDEO ONLY. Never resolve video metadata to native audio,
    // including previously matched local copies or device-side extraction.
    // The visible official YouTube player is opened by the UI coordinator.
    // Spotify tracks are also never raw media; official Spotify playback
    // is launched outside the Breezze audio engine via App Remote / deep link.

    try {
      final catalogId = await _resolveCatalogId(api, track);
      if (catalogId == null) return null;

      final providerIdentity = _providerIdentity(track.id);
      if (providerIdentity != null) {
        final session = await api.startPlaybackSession(
          providerId: providerIdentity.$1,
          providerTrackId: providerIdentity.$2,
          canonicalTrackId: catalogId,
        );
        final sessionId = session['id'] as String?;
        final playback = session['playback'];
        final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
        final expiresAt = playback is Map
            ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
            : null;
        if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
          if (sessionId != null) {
            try { await api.stopPlaybackSession(sessionId); } catch (_) {}
          }
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: streamUrl,
          expiresAtUtc: expiresAt.toUtc(),
          sessionId: sessionId,
          codec: playback['codec'] as String?,
        );
      }

      final preferences = await DownloadPreferencesStore().load();
      final session = await api.startPlaybackSession(
        trackId: catalogId,
        requestedQuality: preferences.streamingQuality,
      );
      final sessionId = session['id'] as String?;
      final playback = session['playback'];
      final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
      final expiresAt = playback is Map
          ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
          : null;
      if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
        if (sessionId != null) {
          try { await api.stopPlaybackSession(sessionId); } catch (_) {}
        }
        return null;
      }

      return PlayableSource(
        trackId: track.id,
        streamUrl: streamUrl,
        expiresAtUtc: expiresAt.toUtc(),
        sessionId: sessionId,
        codec: playback['codec'] as String?,
      );
    } catch (_) {
      // Rights denials and backend/network failures are unavailable playback,
      // not permission to fall back to an unlicensed provider URL.
      return null;
    }
  }

  (String, String)? _providerIdentity(String id) {
    if (!id.startsWith('bz:')) return null;
    final namespaced = id.substring(3);
    final separator = namespaced.indexOf(':');
    if (separator <= 0 || separator == namespaced.length - 1) return null;
    return (namespaced.substring(0, separator), namespaced.substring(separator + 1));
  }

  Future<String?> _resolveCatalogId(BreezzeApi api, TrackInfo track) async {
    if (!track.id.startsWith('bz:')) return track.id;

    final mapDao = _ref.read(catalogIdMapDaoProvider);
    final cached = await mapDao.lookup(track.id);
    if (cached != null) return cached;

    final title = track.title;
    final artist = track.artist;
    final provider = _providerIdentity(track.id);
    if (provider == null || title == null || title.trim().isEmpty ||
        artist == null || artist.trim().isEmpty) {
      return null;
    }

    final resolved = await api.resolveCatalogTrack(
      externalId: track.id,
      source: provider.$1,
      title: title,
      artistName: artist,
      durationSec: track.duration.inSeconds.clamp(1, 86400).toInt(),
    );
    final catalogId = resolved['id'] as String?;
    if (catalogId == null || catalogId.isEmpty) return null;
    await mapDao.save(track.id, catalogId);
    return catalogId;
  }
}

/// Resolver override applied in main() via ProviderScope.
final liveResolverProvider =
    Provider<PlaybackResolver>((ref) => LiveResolver(ref));

// ---------------------------------------------------------------------------
// Storage (path_provider): app-private, survives restarts
// ---------------------------------------------------------------------------

/// App-private downloads directory — the real per-track offline library.
Future<Directory> downloadsDirectory({required String userId}) async {
  // Scope local media by authenticated account. Never share one account's
  // downloaded catalogue with another account on the same device.
  final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (safeUserId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must be non-empty');
  }
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/downloads/$safeUserId');
  await dir.create(recursive: true);
  return dir;
}

// ---------------------------------------------------------------------------
// Favorites — drift-backed store, JSON kept only as the legacy import
// source for the one-shot migration.
// ---------------------------------------------------------------------------

/// A favorited track with its display info.
class FavoriteTrack {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;

  const FavoriteTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs = 0,
  });

  TrackInfo toTrackInfo() => TrackInfo(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: Duration(milliseconds: durationMs),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': durationMs,
      };

  static FavoriteTrack fromJson(Map<String, Object?> json) => FavoriteTrack(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String?,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}

/// Legacy JSON favorites reader — used ONLY by the one-shot migration.
class LegacyFavoritesJson {
  static const _fileName = 'breezze_favorites.json';

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/$_fileName');
  }

  Future<List<FavoriteTrack>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map) FavoriteTrack.fromJson(item.cast<String, Object?>())
      ];
    } catch (_) {
      return [];
    }
  }
}

/// Favorites store — drift-backed (SQLite). Same public API as the
/// JSON version (load / toggle / isFavorite), so screens are unchanged.
class FavoritesStore {
  final FavoritesDao _dao = FavoritesDao(breezzeDb);

  Future<List<FavoriteTrack>> load({String ownerId = 'guest'}) async {
    final rows = await _dao.list(ownerId: ownerId);
    return [
      for (final r in rows)
        FavoriteTrack(
          id: r.id.value,
          title: r.title.value,
          artist: r.artist.value,
          artworkUrl: r.artworkUrl.value,
          durationMs: r.durationMs.value,
        )
    ];
  }

  /// Returns true when the track was added, false when removed.
  Future<bool> toggle(
    FavoriteTrack track, {
    String ownerId = 'guest',
  }) async {
    if (await _dao.contains(track.id, ownerId: ownerId)) {
      await _dao.remove(track.id, ownerId: ownerId);
      return false;
    }
    await _dao.add(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: track.durationMs,
      ownerId: ownerId,
    );
    return true;
  }

  Future<bool> isFavorite(String id, {String ownerId = 'guest'}) =>
      _dao.contains(id, ownerId: ownerId);

  /// One-way hydration from a validated, account-scoped cloud snapshot.
  /// This does not produce local edits or upload the same rows again.
  Future<bool> reconcileCloud(
    String ownerId,
    List<FavoriteTrack> remote,
  ) => _dao.reconcileCloud(
        ownerId: ownerId,
        tracks: [
          for (final track in remote)
            (
              id: track.id,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              durationMs: track.durationMs,
            ),
        ],
      );
}

/// App-wide favorites store provider.
final favoritesStoreProvider =
    Provider<FavoritesStore>((ref) => FavoritesStore());

/// Read-only favorite state is scoped to both account and catalog track.
/// Album/follow providers use the same owner-aware invalidation convention.
typedef FavoriteTrackKey = ({String ownerId, String trackId});

final isTrackFavoriteProvider = FutureProvider.family<bool, FavoriteTrackKey>(
  (ref, key) => ref.read(favoritesStoreProvider)
      .isFavorite(key.trackId, ownerId: key.ownerId),
);

/// Invalidated after a saved-song mutation so the persistent Library tab
/// refreshes without requiring a route restart or another account sign-in.
final favoritesRefreshProvider = StateProvider<int>((ref) => 0);
).hasMatch(id),
    _ => false,
  };

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 120) {
      return ProviderOk(<ProviderTrack>[]);
    }
    try {
      final response = await _ref.read(authSessionProvider.notifier).api
          .searchMusicCatalogs(normalized);
      final shelves = response['providers'];
      final merged = response['tracks'];
      if (merged is! List && shelves is! List) {
        return ProviderError('invalid_music_catalog_response');
      }

      // The server owns source selection and returns one representative per
      // recording. Keep original provider IDs internally for metadata and
      // contractual attribution; they are never a user-facing source picker.
      final entries = <(String, Map)>[];
      if (merged is List) {
        for (final row in merged.whereType<Map>()) {
          final providerId = row['providerId'];
          if (providerId is String) entries.add((providerId, row));
        }
      } else if (shelves is List) {
        // Compatibility during rolling backend deployments.
        for (final name in const ['spotify', 'deezer', 'musicbrainz']) {
          for (final shelf in shelves.whereType<Map>()) {
            if (shelf['providerId'] != name) continue;
            final payload = shelf['result'];
            if (payload is! Map || payload['kind'] != 'ok' ||
                payload['value'] is! List) continue;
            for (final row in (payload['value'] as List).whereType<Map>()) {
              if (entries.any((existing) => _sameRecording(existing.$2, row))) {
                continue;
              }
              entries.add((name, row));
            }
          }
        }
      }

      final tracks = <ProviderTrack>[];
      final seen = <String>{};
      for (final (name, row) in entries) {
        final id = row['providerTrackId'];
        if (id is! String || !_validCatalogId(name, id)) continue;
        final track = _trackFromJson(row, providerId: name);
        if (track.title.isNotEmpty && track.artist.isNotEmpty &&
            seen.add(track.breezzeTrackId)) {
          tracks.add(track);
        }
      }
      final hasValidSource = merged is List ||
          (shelves is List && shelves.whereType<Map>().any((shelf) {
            final result = shelf['result'];
            return result is Map && result['kind'] == 'ok';
          }));
      return hasValidSource
          ? ProviderOk(tracks)
          : ProviderError('music_catalogs_unavailable');
    } catch (_) {
      return ProviderError('music_catalog_network_error');
    }
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async {
    try {
      final separator = providerTrackId.indexOf(':');
      if (separator <= 0 || separator == providerTrackId.length - 1) {
        return ProviderError('invalid_provider_track_id');
      }
      final source = providerTrackId.substring(0, separator);
      final sourceTrackId = providerTrackId.substring(separator + 1);
      final data = await _ref.read(authSessionProvider.notifier).api
          .getProviderTrack(source, sourceTrackId);
      final value = data['value'];
      if (data['kind'] != 'ok' || value is! Map) {
        return ProviderError('track_metadata_unavailable');
      }
      return ProviderOk(_trackFromJson(value, providerId: source));
    } catch (_) {
      return ProviderError('network_error');
    }
  }

}

/// The app-wide metadata/search adapter; it is not a playback authority.
final catalogSourceProvider =
    Provider<ProviderAdapter>((ref) => BackendCatalogSourceAdapter(ref));

/// The lyrics provider.
final lyricsProvider =
    Provider<LyricsProvider>((ref) => LyricsProvider(HttpLyrics()));

/// Metadata search chain. No source in this chain grants playback rights.
final sourceChainProvider = Provider<SourceChain>((ref) => SourceChain([
      ref.watch(catalogSourceProvider),
    ]));

/// The playback resolver. Catalog metadata is converged to a canonical
/// backend track ID, then full-stream playback is authorized by the backend.
/// The mobile client never turns catalogue metadata directly into a
/// playable stream URL.
class LiveResolver implements PlaybackResolver {
  final Ref _ref;

  LiveResolver(this._ref);

  @override
  Future<PlayableSource?> resolve(TrackInfo track) async {
    // Explicit native Deezer PREVIEW only (30 seconds at most).
    // The authorized full Deezer recording remains inside Deezer's app.
    // External streaming services do not grant Breezze raw audio.
    if (isYouTubeSongId(track.id) ||
        track.id.startsWith('bz:spotify:') ||
        track.id.startsWith('bz:deezer:') ||
        isDeezerPreview(track.id) ||
        track.id.startsWith('bzv:')) {
      return null;
    }
    final auth = _ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return null;

    final api = _ref.read(authSessionProvider.notifier).api;
    if (api.accessToken == null) return null;

    if (isPublicAudioProofTrackId(track.id)) {
      const proofEnabled = bool.fromEnvironment(
        'BREEZZE_PUBLIC_AUDIO_PROOF',
        defaultValue: false,
      );
      if (!proofEnabled) return null;
      try {
        final grant = await api.audioProofPlayback();
        final url = grant['streamUrl'] as String?;
        final expiry = DateTime.tryParse(grant['expiresAt'] as String? ?? '');
        const expectedUrl =
            'https://upload.wikimedia.org/wikipedia/commons/transcoded/'
            '1/1f/Promise.ogg/Promise.ogg.mp3';
        if (grant['id'] != track.id ||
            grant['source'] != 'wikimedia_commons' ||
            grant['offlineAllowed'] != false ||
            url != expectedUrl ||
            expiry == null ||
            !isUsableRemoteAudioGrant(url!, expiry)) {
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: url,
          expiresAtUtc: expiry.toUtc(),
          codec: 'mp3',
        );
      } catch (_) {
        return null;
      }
    }

    // YouTube is VIDEO ONLY. Never resolve video metadata to native audio,
    // including previously matched local copies or device-side extraction.
    // The visible official YouTube player is opened by the UI coordinator.
    // Spotify tracks are also never raw media; official Spotify playback
    // is launched outside the Breezze audio engine via App Remote / deep link.

    try {
      final catalogId = await _resolveCatalogId(api, track);
      if (catalogId == null) return null;

      final providerIdentity = _providerIdentity(track.id);
      if (providerIdentity != null) {
        final session = await api.startPlaybackSession(
          providerId: providerIdentity.$1,
          providerTrackId: providerIdentity.$2,
          canonicalTrackId: catalogId,
        );
        final sessionId = session['id'] as String?;
        final playback = session['playback'];
        final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
        final expiresAt = playback is Map
            ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
            : null;
        if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
          if (sessionId != null) {
            try { await api.stopPlaybackSession(sessionId); } catch (_) {}
          }
          return null;
        }
        return PlayableSource(
          trackId: track.id,
          streamUrl: streamUrl,
          expiresAtUtc: expiresAt.toUtc(),
          sessionId: sessionId,
          codec: playback['codec'] as String?,
        );
      }

      final preferences = await DownloadPreferencesStore().load();
      final session = await api.startPlaybackSession(
        trackId: catalogId,
        requestedQuality: preferences.streamingQuality,
      );
      final sessionId = session['id'] as String?;
      final playback = session['playback'];
      final streamUrl = playback is Map ? playback['streamUrl'] as String? : null;
      final expiresAt = playback is Map
          ? DateTime.tryParse(playback['expiresAt'] as String? ?? '')
          : null;
      if (streamUrl == null || expiresAt == null || sessionId == null ||
            !isUsableRemoteAudioGrant(streamUrl, expiresAt)) {
        if (sessionId != null) {
          try { await api.stopPlaybackSession(sessionId); } catch (_) {}
        }
        return null;
      }

      return PlayableSource(
        trackId: track.id,
        streamUrl: streamUrl,
        expiresAtUtc: expiresAt.toUtc(),
        sessionId: sessionId,
        codec: playback['codec'] as String?,
      );
    } catch (_) {
      // Rights denials and backend/network failures are unavailable playback,
      // not permission to fall back to an unlicensed provider URL.
      return null;
    }
  }

  (String, String)? _providerIdentity(String id) {
    if (!id.startsWith('bz:')) return null;
    final namespaced = id.substring(3);
    final separator = namespaced.indexOf(':');
    if (separator <= 0 || separator == namespaced.length - 1) return null;
    return (namespaced.substring(0, separator), namespaced.substring(separator + 1));
  }

  Future<String?> _resolveCatalogId(BreezzeApi api, TrackInfo track) async {
    if (!track.id.startsWith('bz:')) return track.id;

    final mapDao = _ref.read(catalogIdMapDaoProvider);
    final cached = await mapDao.lookup(track.id);
    if (cached != null) return cached;

    final title = track.title;
    final artist = track.artist;
    final provider = _providerIdentity(track.id);
    if (provider == null || title == null || title.trim().isEmpty ||
        artist == null || artist.trim().isEmpty) {
      return null;
    }

    final resolved = await api.resolveCatalogTrack(
      externalId: track.id,
      source: provider.$1,
      title: title,
      artistName: artist,
      durationSec: track.duration.inSeconds.clamp(1, 86400).toInt(),
    );
    final catalogId = resolved['id'] as String?;
    if (catalogId == null || catalogId.isEmpty) return null;
    await mapDao.save(track.id, catalogId);
    return catalogId;
  }
}

/// Resolver override applied in main() via ProviderScope.
final liveResolverProvider =
    Provider<PlaybackResolver>((ref) => LiveResolver(ref));

// ---------------------------------------------------------------------------
// Storage (path_provider): app-private, survives restarts
// ---------------------------------------------------------------------------

/// App-private downloads directory — the real per-track offline library.
Future<Directory> downloadsDirectory({required String userId}) async {
  // Scope local media by authenticated account. Never share one account's
  // downloaded catalogue with another account on the same device.
  final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (safeUserId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must be non-empty');
  }
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/downloads/$safeUserId');
  await dir.create(recursive: true);
  return dir;
}

// ---------------------------------------------------------------------------
// Favorites — drift-backed store, JSON kept only as the legacy import
// source for the one-shot migration.
// ---------------------------------------------------------------------------

/// A favorited track with its display info.
class FavoriteTrack {
  final String id;
  final String title;
  final String artist;
  final String? artworkUrl;
  final int durationMs;

  const FavoriteTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.durationMs = 0,
  });

  TrackInfo toTrackInfo() => TrackInfo(
        id: id,
        title: title,
        artist: artist,
        artworkUrl: artworkUrl,
        duration: Duration(milliseconds: durationMs),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkUrl': artworkUrl,
        'durationMs': durationMs,
      };

  static FavoriteTrack fromJson(Map<String, Object?> json) => FavoriteTrack(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        artworkUrl: json['artworkUrl'] as String?,
        durationMs: json['durationMs'] as int? ?? 0,
      );
}

/// Legacy JSON favorites reader — used ONLY by the one-shot migration.
class LegacyFavoritesJson {
  static const _fileName = 'breezze_favorites.json';

  Future<File> _file() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/$_fileName');
  }

  Future<List<FavoriteTrack>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return [
        for (final item in raw)
          if (item is Map) FavoriteTrack.fromJson(item.cast<String, Object?>())
      ];
    } catch (_) {
      return [];
    }
  }
}

/// Favorites store — drift-backed (SQLite). Same public API as the
/// JSON version (load / toggle / isFavorite), so screens are unchanged.
class FavoritesStore {
  final FavoritesDao _dao = FavoritesDao(breezzeDb);

  Future<List<FavoriteTrack>> load({String ownerId = 'guest'}) async {
    final rows = await _dao.list(ownerId: ownerId);
    return [
      for (final r in rows)
        FavoriteTrack(
          id: r.id.value,
          title: r.title.value,
          artist: r.artist.value,
          artworkUrl: r.artworkUrl.value,
          durationMs: r.durationMs.value,
        )
    ];
  }

  /// Returns true when the track was added, false when removed.
  Future<bool> toggle(
    FavoriteTrack track, {
    String ownerId = 'guest',
  }) async {
    if (await _dao.contains(track.id, ownerId: ownerId)) {
      await _dao.remove(track.id, ownerId: ownerId);
      return false;
    }
    await _dao.add(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artworkUrl: track.artworkUrl,
      durationMs: track.durationMs,
      ownerId: ownerId,
    );
    return true;
  }

  Future<bool> isFavorite(String id, {String ownerId = 'guest'}) =>
      _dao.contains(id, ownerId: ownerId);

  /// One-way hydration from a validated, account-scoped cloud snapshot.
  /// This does not produce local edits or upload the same rows again.
  Future<bool> reconcileCloud(
    String ownerId,
    List<FavoriteTrack> remote,
  ) => _dao.reconcileCloud(
        ownerId: ownerId,
        tracks: [
          for (final track in remote)
            (
              id: track.id,
              title: track.title,
              artist: track.artist,
              artworkUrl: track.artworkUrl,
              durationMs: track.durationMs,
            ),
        ],
      );
}

/// App-wide favorites store provider.
final favoritesStoreProvider =
    Provider<FavoritesStore>((ref) => FavoritesStore());

/// Read-only favorite state is scoped to both account and catalog track.
/// Album/follow providers use the same owner-aware invalidation convention.
typedef FavoriteTrackKey = ({String ownerId, String trackId});

final isTrackFavoriteProvider = FutureProvider.family<bool, FavoriteTrackKey>(
  (ref, key) => ref.read(favoritesStoreProvider)
      .isFavorite(key.trackId, ownerId: key.ownerId),
);

/// Invalidated after a saved-song mutation so the persistent Library tab
/// refreshes without requiring a route restart or another account sign-in.
final favoritesRefreshProvider = StateProvider<int>((ref) => 0);
