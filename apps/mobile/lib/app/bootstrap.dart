import 'dart:convert';
import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/audio/just_audio_engine_adapter.dart';
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
