import 'dart:convert';

import 'package:http/http.dart' as http;

/// Breezze backend API client — thin transport for /api/v1.
///
/// No secrets: the backend is Breezze's own; JWT access + refresh tokens
/// are stored by the session controller, never hardcoded.
class BreezzeApi {
  BreezzeApi({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  String? accessToken;
  Future<bool> Function()? onUnauthorized;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    Future<http.Response> send() => _client.post(
          _uri(path),
          headers: _headers,
          body: jsonEncode(body),
        );
    var response = await send();
    if (response.statusCode == 401 &&
        path != '/auth/refresh' &&
        path != '/auth/login' &&
        path != '/auth/register' &&
        !path.startsWith('/auth/mfa/') &&
        onUnauthorized != null &&
        await onUnauthorized!()) {
      response = await send();
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    Future<http.Response> send() =>
        _client.get(_uri(path), headers: _headers);
    var response = await send();
    if (response.statusCode == 401 &&
        onUnauthorized != null &&
        await onUnauthorized!()) {
      response = await send();
    }
    return _decode(response);
  }
  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    Future<http.Response> send() => _client.patch(
          _uri(path),
          headers: _headers,
          body: jsonEncode(body),
        );
    var response = await send();
    if (response.statusCode == 401 &&
        onUnauthorized != null &&
        await onUnauthorized!()) {
      response = await send();
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> _delete(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    Future<http.Response> send() => _client.delete(
          _uri(path),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        );
    var response = await send();
    if (response.statusCode == 401 &&
        onUnauthorized != null &&
        await onUnauthorized!()) {
      response = await send();
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      final error = body['error'];
      throw BreezzeApiException(
        code: error is Map && error['code'] is String
            ? error['code'] as String
            : 'HTTP_${response.statusCode}',
        message: error is Map && error['message'] is String
            ? error['message'] as String
            : 'Request failed',
      );
    }
    final data = body['data'];
    return data is Map<String, dynamic> ? data : body;
  }


  Future<Map<String, dynamic>> searchMusic(String query) =>
      _get('/search?q=${Uri.encodeQueryComponent(query)}');

  /// Federated catalog search. Each provider returns its own result envelope;
  /// a single provider outage must not hide results from the other catalogs.
  Future<Map<String, dynamic>> searchAllProviders(String query) =>
      _get('/providers/search?q=${Uri.encodeQueryComponent(query)}');

  Future<Map<String, dynamic>> getProviderTrack(
    String providerId,
    String providerTrackId,
  ) =>
      _get('/providers/${Uri.encodeComponent(providerId)}/tracks/${Uri.encodeComponent(providerTrackId)}');


  // ---- public catalog discovery (metadata only; never playback grants) ----
  Future<Map<String, dynamic>> discoveryDailyTop100({String country = 'us'}) =>
      _get('/discovery/charts/daily-top-100?country=${Uri.encodeQueryComponent(country)}');

  Future<Map<String, dynamic>> discoverySongsChart({String country = 'us'}) =>
      _get('/discovery/charts/songs?country=${Uri.encodeQueryComponent(country)}');

  Future<Map<String, dynamic>> discoveryNewReleases({String country = 'us'}) =>
      _get('/discovery/releases/albums?country=${Uri.encodeQueryComponent(country)}');

  Future<Map<String, dynamic>> discoveryMusicVideos({String query = 'official music video'}) =>
      _get('/discovery/videos?q=${Uri.encodeQueryComponent(query)}');

  Future<Map<String, dynamic>> discoveryConcerts({String country = 'TZ', String? city}) =>
      _get('/discovery/concerts?country=${Uri.encodeQueryComponent(country)}${city == null || city.trim().isEmpty ? '' : '&city=${Uri.encodeQueryComponent(city)}'}');

  Future<Map<String, dynamic>> discoveryTrackSearch(String query) =>
      _get('/discovery/tracks/search?q=${Uri.encodeQueryComponent(query)}');

  Future<Map<String, dynamic>> discoveryArtistSearch(String query) =>
      _get('/discovery/artists/search?q=${Uri.encodeQueryComponent(query)}');

  Future<Map<String, dynamic>> discoveryArtistAlbums(String artistId) =>
      _get('/discovery/artists/${Uri.encodeComponent(artistId)}/albums');

  Future<Map<String, dynamic>> discoveryAlbumTracks(String albumId) =>
      _get('/discovery/albums/${Uri.encodeComponent(albumId)}/tracks');

  // ---- auth ----

  Future<AuthResponse> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    final data = await _post('/auth/register', {
      'email': email,
      'password': password,
      if (displayName != null) 'displayName': displayName,
    });
    return AuthResponse.fromJson(data);
  }

  Future<AuthResponse> login(String email, String password) async {
    final data = await _post('/auth/login', {
      'email': email,
      'password': password,
    });
    return AuthResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> resolveCatalogTrack({
    required String externalId,
    required String source,
    required String title,
    required String artistName,
    required int durationSec,
  }) =>
      _post('/catalog/resolve', {
        'externalId': externalId,
        'source': source,
        'title': title,
        'artistName': artistName,
        'durationSec': durationSec,
      });

  Future<Map<String, dynamic>> startPlaybackSession({
    String? trackId,
    String? requestedQuality,
    String? providerId,
    String? providerTrackId,
    String? canonicalTrackId,
  }) =>
      _post('/playback/sessions', {
        if (trackId != null) 'trackId': trackId,
        if (requestedQuality != null) 'requestedQuality': requestedQuality,
        if (providerId != null) 'providerId': providerId,
        if (providerTrackId != null) 'providerTrackId': providerTrackId,
        if (canonicalTrackId != null) 'canonicalTrackId': canonicalTrackId,
      });

  Future<Map<String, dynamic>> playbackHeartbeat({
    required String sessionId,
    required String eventId,
    required int sequence,
  }) =>
      _post('/playback/sessions/${Uri.encodeComponent(sessionId)}/heartbeat', {
        'eventId': eventId,
        'sequence': sequence,
      });

  Future<void> pausePlaybackSession(String sessionId) async {
    await _post('/playback/sessions/${Uri.encodeComponent(sessionId)}/pause', const {});
  }

  Future<void> resumePlaybackSession(String sessionId) async {
    await _post('/playback/sessions/${Uri.encodeComponent(sessionId)}/resume', const {});
  }

  Future<void> stopPlaybackSession(String sessionId) async {
    await _post('/playback/sessions/${Uri.encodeComponent(sessionId)}/stop', const {});
  }

  Future<Map<String, dynamic>> resolveProviderPlayback({
    required String providerId,
    required String providerTrackId,
    required String canonicalTrackId,
    required String territory,
  }) =>
      _post('/playback/provider/resolve', {
        'providerId': providerId,
        'providerTrackId': providerTrackId,
        'canonicalTrackId': canonicalTrackId,
        'territory': territory,
      });

  Future<Map<String, dynamic>> resolvePlayback({
    required String trackId,
    required String territory,
    String? requestedQuality,
  }) =>
      _post('/playback/resolve', {
        'trackId': trackId,
        'territory': territory,
        if (requestedQuality != null) 'requestedQuality': requestedQuality,
      });

  Future<Map<String, dynamic>> authorizeDownload({
    required String trackId,
    required String territory,
  }) =>
      _post('/downloads', {
        'trackId': trackId,
        'territory': territory,
      });

  Future<Map<String, dynamic>> revalidateOfflineLease({
    required String trackId,
    required String territory,
  }) =>
      _post('/downloads/$trackId/revalidate', {'territory': territory});

  Future<AuthResponse> refresh(String refreshToken) async {
    final data = await _post('/auth/refresh', {
      'refreshToken': refreshToken,
    });
    return AuthResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> beginMfaSetup(String password) =>
      _post('/auth/mfa/setup', {'password': password});

  Future<Map<String, dynamic>> verifyMfaSetup(String code) =>
      _post('/auth/mfa/setup/verify', {'code': code});

  Future<Map<String, dynamic>> verifyMfa(String code) =>
      _post('/auth/mfa/verify', {'code': code});

  Future<void> logout(String refreshToken) async {
    await _post('/auth/logout', {'refreshToken': refreshToken});
  }

  Future<Map<String, dynamic>> me() async => _get('/auth/me');

  // ---- account and sessions ----

  Future<Map<String, dynamic>> profile() => _get('/users/me');

  Future<Map<String, dynamic>> updateProfile({required String displayName}) =>
      _patch('/users/me', {'displayName': displayName});

  Future<void> deleteAccount({required String password}) async {
    await _delete('/users/me', body: {'password': password});
  }

  Future<List<Map<String, dynamic>>> sessions() async {
    final data = await _get('/auth/sessions');
    return _asMapList(
      data['sessions'] ?? data['items'] ?? data['data'] ?? data,
    );
  }

  Future<void> revokeSession(String sessionId) async {
    await _delete('/auth/sessions/${Uri.encodeComponent(sessionId)}');
  }

  // ---- home and playlists ----

  Future<List<Map<String, dynamic>>> homeFeed() async =>
      _asMapList(await _get('/home'));

  Future<Map<String, dynamic>> recordPlay(String trackId) =>
      _post('/home/plays', {'trackId': trackId});

  Future<Map<String, dynamic>> replaySummary() => _get('/replay');

  Future<List<Map<String, dynamic>>> playlists() async =>
      _asMapList(await _get('/playlists'));

  Future<Map<String, dynamic>> createPlaylist(String name) =>
      _post('/playlists', {'name': name});

  Future<Map<String, dynamic>> getPlaylist(String playlistId) =>
      _get('/playlists/${Uri.encodeComponent(playlistId)}');

  Future<Map<String, dynamic>> addPlaylistTrack(
    String playlistId,
    String trackId,
  ) =>
      _post('/playlists/${Uri.encodeComponent(playlistId)}/tracks', {
        'trackId': trackId,
      });

  Future<void> removePlaylistTrack(String playlistId, String trackId) async {
    await _delete(
      '/playlists/${Uri.encodeComponent(playlistId)}/tracks/'
      '${Uri.encodeComponent(trackId)}',
    );
  }

  Future<Map<String, dynamic>> renamePlaylist(
    String playlistId,
    String name,
  ) =>
      _patch('/playlists/${Uri.encodeComponent(playlistId)}', {'name': name});

  Future<void> deletePlaylist(String playlistId) async {
    await _delete('/playlists/${Uri.encodeComponent(playlistId)}');
  }

  // ---- notifications ----

  Future<List<Map<String, dynamic>>> notifications() async =>
      _asMapList(await _get('/notifications'));

  Future<Map<String, dynamic>> markNotificationRead(String id) =>
      _post('/notifications/${Uri.encodeComponent(id)}/read', const {});

  List<Map<String, dynamic>> _asMapList(Object? value) {
    if (value is List) {
      return value.whereType<Map>().map((item) {
        return item.map((key, value) => MapEntry(key.toString(), value));
      }).toList();
    }
    if (value is Map && value['data'] is List) {
      return _asMapList(value['data']);
    }
    return const [];
  }
}

class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final String email;
  final bool mfaRequired;
  final bool mfaSetupRequired;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.email,
    this.mfaRequired = false,
    this.mfaSetupRequired = false,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return AuthResponse(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      userId: user is Map ? (user['id'] as String? ?? '') : '',
      email: user is Map ? (user['email'] as String? ?? '') : '',
      mfaRequired: json['mfaRequired'] == true,
      mfaSetupRequired: json['mfaSetupRequired'] == true,
    );
  }
}

class BreezzeApiException implements Exception {
  final String code;
  final String message;
  const BreezzeApiException({required this.code, required this.message});

  @override
  String toString() => '$code: $message';
}
