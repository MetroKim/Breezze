/// BitChord adapter — the real backend connection for music fetch and
/// search. Talks to the BitChord music backend (YouTube Music
/// innerTube-style API).
///
/// The request signer is an injected seam (SignerService); the API key
/// comes from configuration at bootstrap, never hard-coded here.
library;

import 'bz_track.dart';
import 'provider_adapter.dart';

/// Minimal HTTP seam — implemented in the app with package:http.
abstract interface class BackendHttp {
  Future<Object?> postJson(
    String url,
    Map<String, Object?> body, {
    Map<String, String> headers,
  });
}

/// Request context used for backend calls.
const Map<String, Object?> _clientContext = {
  'context': {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20240101.01.00',
      'hl': 'en',
      'gl': 'US',
    },
  },
};

/// Recursively collects every value stored under [key] in [node].
List<Object?> _walk(Object? node, String key) {
  final out = <Object?>[];
  void visit(Object? n) {
    if (n is Map) {
      n.forEach((k, v) {
        if (k == key) out.add(v);
        visit(v);
      });
    } else if (n is List) {
      for (final item in n) {
        visit(item);
      }
    }
  }

  visit(node);
  return out;
}

String? _runsText(Object? node) {
  if (node is! Map) return null;
  final runs = node['runs'];
  if (runs is! List) return null;
  final texts = <String>[];
  for (final run in runs) {
    if (run is Map && run['text'] is String) {
      texts.add(run['text'] as String);
    }
  }
  return texts.isEmpty ? null : texts.join('');
}

String? _flexColumnText(Object? item, int index) {
  final cols = _walk(item, 'musicResponsiveListItemFlexColumnRenderer');
  if (index >= cols.length) return null;
  return _runsText(cols[index]);
}

Duration _durationOf(Object? item) {
  final fixed = _walk(item, 'musicResponsiveListItemFixedColumnRenderer');
  if (fixed.isEmpty) return Duration.zero;
  final text = _runsText(fixed.first);
  if (text == null) return Duration.zero;
  final parts = text.split(':');
  try {
    if (parts.length == 2) {
      return Duration(
          seconds: int.parse(parts[0]) * 60 + int.parse(parts[1]));
    }
    if (parts.length == 3) {
      return Duration(
          seconds:
              int.parse(parts[0]) * 3600 +
              int.parse(parts[1]) * 60 +
              int.parse(parts[2]));
    }
  } catch (_) {
    return Duration.zero;
  }
  return Duration.zero;
}

String? _videoIdOf(Object? item) {
  final datas = _walk(item, 'playlistItemData');
  for (final data in datas) {
    if (data is Map && data['videoId'] is String) {
      return data['videoId'] as String;
    }
  }
  return null;
}

ProviderTrack? _toTrack(Object? item) {
  if (item is! Map) return null;
  final videoId = _videoIdOf(item);
  final title = _flexColumnText(item, 0);
  if (videoId == null || title == null) return null;
  return ProviderTrack(
    breezzeTrackId: 'bz:$videoId',
    providerTrackId: videoId,
    title: title,
    artist: _flexColumnText(item, 1) ?? 'Unknown artist',
    duration: _durationOf(item),
  );
}

class BitChordAdapter implements ProviderAdapter {
  final BackendHttp http;
  final SignerService? signer;
  final String baseUrl;
  final String apiKey;

  BitChordAdapter({
    required this.http,
    required this.apiKey,
    this.baseUrl = 'https://music.youtube.com/youtubei/v1',
    this.signer,
  });

  @override
  String get providerId => 'bitchord';

  @override
  String get adapterVersion => '1.0.0';

  /// Full-track playback requires a maintained signer seam.
  @override
  bool get supportsPlayback => signer != null;

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) async {
    try {
      final body = <String, Object?>{..._clientContext, 'query': query};
      final data = await http.postJson('$baseUrl/search?key=$apiKey', body);
      final items = _walk(data, 'musicResponsiveListItemRenderer');
      final tracks = <ProviderTrack>[];
      for (final item in items) {
        final track = _toTrack(item);
        if (track != null) tracks.add(track);
      }
      if (tracks.isEmpty) return ProviderError('empty_result');
      return ProviderOk(tracks);
    } catch (_) {
      return ProviderError('network_error');
    }
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async {
    return ProviderUnsupported('use_search');
  }

  @override
  Future<ProviderOp<String>> resolvePlayback(
      String providerTrackId, ProviderUserContext userContext) async {
    if (signer == null) {
      return ProviderUnsupported('signer_not_configured');
    }
    final videoId = providerTrackId.startsWith('bz:')
        ? providerTrackId.substring(3)
        : providerTrackId;
    try {
      final body = <String, Object?>{..._clientContext, 'videoId': videoId};
      final data = await http.postJson('$baseUrl/player?key=$apiKey', body);
      final formats = _walk(data, 'adaptiveFormats');

      String? bestUrl;
      var bestBitrate = -1;
      for (final format in formats) {
        if (format is! Map) continue;
        final mime = format['mimeType'];
        if (mime is! String || !mime.startsWith('audio/')) continue;
        if (format['signatureCipher'] != null) continue;
        final bitrate = (format['bitrate'] as num?)?.toInt() ?? 0;
        if (bitrate > bestBitrate) {
          final url = format['url'];
          if (url is String) {
            bestBitrate = bitrate;
            bestUrl = url;
          }
        }
      }
      if (bestUrl == null) {
        return ProviderUnsupported('stream_requires_decipherer');
      }
      return ProviderOk(await signer!.sign(bestUrl, const {}));
    } catch (_) {
      return ProviderError('network_error');
    }
  }

  @override
  Future<ProviderOp<String>> getAttributionRequirements(
      String providerTrackId) async {
    return ProviderOk('Breezze via BitChord backend');
  }
}
