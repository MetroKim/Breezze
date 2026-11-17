import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';

import '../features/player/player_controller.dart';

/// Composition root — the real, working wiring at startup.
///
/// No user API key anywhere: search + playback run through
/// youtube_explode_dart (keyless), lyrics through LRCLIB (keyless).

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

/// The real playback source provider — app-wide singleton.
final youtubeSourceProvider =
    Provider<YoutubeSourceAdapter>((ref) => YoutubeSourceAdapter());

/// The lyrics provider.
final lyricsProvider =
    Provider<LyricsProvider>((ref) => LyricsProvider(HttpLyrics()));

/// The source chain: youtube_explode primary.
final sourceChainProvider = Provider<SourceChain>((ref) => SourceChain([
      ref.watch(youtubeSourceProvider),
    ]));

/// The playback resolver: resolves through the live source.
class LiveResolver implements PlaybackResolver {
  final YoutubeSourceAdapter source;

  LiveResolver(this.source);

  @override
  Future<PlayableSource?> resolve(String trackId) async {
    final videoId =
        trackId.startsWith('bz:') ? trackId.substring(3) : trackId;
    final stream = await source.resolveStream(videoId);
    if (stream == null) return null;
    return PlayableSource(
      trackId: trackId,
      streamUrl: stream.streamUrl,
      expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 6)),
      codec: stream.codec,
    );
  }
}

/// Resolver override applied in main() via ProviderScope.
final liveResolverProvider = Provider<PlaybackResolver>(
    (ref) => LiveResolver(ref.watch(youtubeSourceProvider)));

/// Attach the native engine to the global player.
void attachPlaybackEngine(ProviderContainer container) {
  final player = container.read(playerControllerProvider.notifier);
  player.attachEngine(JustAudioEngineAdapter());
}

// ---------------------------------------------------------------------------
// Storage (path_provider): app-private, survives restarts
// ---------------------------------------------------------------------------

/// App-private downloads directory — the real per-track offline library.
Future<Directory> downloadsDirectory() async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/downloads');
  await dir.create(recursive: true);
  return dir;
}

// ---------------------------------------------------------------------------
// Favorites store — simple JSON persistence, no Drift yet
// ---------------------------------------------------------------------------

/// A favorited track with its display info, persisted to JSON.
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

/// Favorites persistence: JSON file in app documents.
class FavoritesStore {
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

  Future<void> save(List<FavoriteTrack> tracks) async {
    final file = await _file();
    await file.writeAsString(
        jsonEncode([for (final t in tracks) t.toJson()]));
  }

  Future<bool> toggle(FavoriteTrack track) async {
    final tracks = await load();
    final exists = tracks.any((t) => t.id == track.id);
    if (exists) {
      await save(tracks.where((t) => t.id != track.id).toList());
      return false; // removed
    }
    await save([...tracks, track]);
    return true; // added
  }

  Future<bool> isFavorite(String id) async =>
      (await load()).any((t) => t.id == id);
}

/// App-wide favorites store provider.
final favoritesStoreProvider = Provider<FavoritesStore>((ref) => FavoritesStore());
