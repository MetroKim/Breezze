import 'dart:convert';
import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/audio/just_audio_engine_adapter.dart';
import '../features/player/player_controller.dart';

/// Composition root — constructs the real backend wiring at startup.
///
/// BitChord's model: no user API key. Client config is scraped from the
/// public music.youtube.com homepage at runtime (InnertubeConfig.fetch).
class HttpBackend implements BackendHttp {
  final http.Client _client = http.Client();

  @override
  Future<Object?> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json', ...headers},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw HttpException('backend_${response.statusCode}');
    }
    return jsonDecode(response.body);
  }

  @override
  Future<String> getText(String url) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      },
    );
    if (response.statusCode != 200) {
      throw HttpException('scrape_${response.statusCode}');
    }
    return response.body;
  }
}

/// Builds the BitChord-primary source chain — zero user credentials.
SourceChain buildSourceChain() => SourceChain([BitChordAdapter(http: HttpBackend())]);

/// App-wide providers.
final sourceChainProvider =
    Provider<SourceChain>((ref) => buildSourceChain());

/// The playback resolver: resolves through the source chain.
class SourceChainResolver implements PlaybackResolver {
  final SourceChain chain;

  SourceChainResolver(this.chain);

  @override
  Future<PlayableSource?> resolve(String trackId) async {
    final result = await chain.resolve(
      trackId,
      ProviderUserContext(
        userId: 'local',
        territory: Platform.localeName.split('_').last,
        subscriptionTier: 'premium',
      ),
    );
    if (result is! SourceChainOk) return null;
    return PlayableSource(
      trackId: trackId,
      streamUrl: result.streamUrl,
      expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 6)),
    );
  }
}

/// The resolver override applied once at app start via ProviderScope.
final liveResolverProvider =
    Provider<PlaybackResolver>((ref) => SourceChainResolver(buildSourceChain()));

/// Called from main() to attach the native engine to the global player.
void attachPlaybackEngine(ProviderContainer container) {
  final player =
      container.read(playerControllerProvider.notifier);
  player.attachEngine(JustAudioEngineAdapter());
}
