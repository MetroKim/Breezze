import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _musicOrigin = 'https://music.youtube.com';
const _defaultClientVersion = '1.20251006.03.00';
const _sessionStorageKey = 'breezze.youtube_music.session.v1';

class YouTubeMusicConnection {
  const YouTubeMusicConnection({
    required this.connected,
    this.authUser,
    this.clientVersion,
    this.connectedAt,
    this.displayName,
    this.email,
  });

  const YouTubeMusicConnection.disconnected()
      : connected = false,
        authUser = null,
        clientVersion = null,
        connectedAt = null,
        displayName = null,
        email = null;

  final bool connected;
  final String? authUser;
  final String? clientVersion;
  final DateTime? connectedAt;
  final String? displayName;
  final String? email;
}

class YouTubeMusicSessionException implements Exception {
  const YouTubeMusicSessionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

String youtubeMusicCookieHeader(Map<String, String> cookies) {
  final entries = cookies.entries
      .where((entry) => entry.key.trim().isNotEmpty && entry.value.isNotEmpty)
      .toList(growable: false)
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
}

String? youtubeMusicSigningSecret(Map<String, String> cookies) {
  for (final name in const [
    'SAPISID',
    '__Secure-3PAPISID',
    '__Secure-1PAPISID',
  ]) {
    final value = cookies[name];
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String youtubeMusicAuthorization(
  String secret, {
  required int unixSeconds,
  String origin = _musicOrigin,
}) {
  final digest = sha1.convert(
    utf8.encode('$unixSeconds $secret $origin'),
  );
  return 'SAPISIDHASH ${unixSeconds}_$digest';
}

class YouTubeMusicSessionController
    extends AsyncNotifier<YouTubeMusicConnection> {
  static const _storage = FlutterSecureStorage();

  @override
  Future<YouTubeMusicConnection> build() async {
    final raw = await _storage.read(key: _sessionStorageKey);
    if (raw == null || raw.isEmpty) {
      return const YouTubeMusicConnection.disconnected();
    }
    try {
      final stored = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final cookies = Map<String, String>.from(stored['cookies'] as Map);
      if (youtubeMusicSigningSecret(cookies) == null) {
        await _storage.delete(key: _sessionStorageKey);
        return const YouTubeMusicConnection.disconnected();
      }
      return YouTubeMusicConnection(
        connected: true,
        authUser: stored['authUser'] as String?,
        clientVersion: stored['clientVersion'] as String?,
        connectedAt: DateTime.tryParse(stored['connectedAt'] as String? ?? ''),
        displayName: stored['displayName'] as String?,
        email: stored['email'] as String?,
      );
    } catch (_) {
      await _storage.delete(key: _sessionStorageKey);
      return const YouTubeMusicConnection.disconnected();
    }
  }

  Future<void> connect({
    required Map<String, String> cookies,
    String? authUser,
    String? clientVersion,
  }) async {
    final secret = youtubeMusicSigningSecret(cookies);
    if (secret == null) {
      throw const YouTubeMusicSessionException(
        'YTMUSIC_SESSION_INCOMPLETE',
        'YouTube Music has not finished signing in yet.',
      );
    }

    final normalizedAuthUser = authUser?.trim().isNotEmpty == true
        ? authUser!.trim()
        : '0';
    final normalizedVersion = clientVersion?.trim().isNotEmpty == true
        ? clientVersion!.trim()
        : _defaultClientVersion;

    final account = await _validate(
      cookies: cookies,
      secret: secret,
      authUser: normalizedAuthUser,
      clientVersion: normalizedVersion,
    );

    final connectedAt = DateTime.now().toUtc();
    await _storage.write(
      key: _sessionStorageKey,
      value: jsonEncode({
        'cookies': cookies,
        'authUser': normalizedAuthUser,
        'clientVersion': normalizedVersion,
        'connectedAt': connectedAt.toIso8601String(),
        'displayName': account.displayName,
        'email': account.email,
      }),
    );
    state = AsyncData(YouTubeMusicConnection(
      connected: true,
      authUser: normalizedAuthUser,
      clientVersion: normalizedVersion,
      connectedAt: connectedAt,
      displayName: account.displayName,
      email: account.email,
    ));
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _sessionStorageKey);
    state = const AsyncData(YouTubeMusicConnection.disconnected());
  }

  Future<_ValidatedAccount> _validate({
    required Map<String, String> cookies,
    required String secret,
    required String authUser,
    required String clientVersion,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final response = await http
        .post(
          Uri.parse(
            '$_musicOrigin/youtubei/v1/account/account_menu?prettyPrint=false',
          ),
          headers: {
            'Authorization': youtubeMusicAuthorization(
              secret,
              unixSeconds: now,
            ),
            'Cookie': youtubeMusicCookieHeader(cookies),
            'Content-Type': 'application/json',
            'Origin': _musicOrigin,
            'X-Origin': _musicOrigin,
            'X-Goog-AuthUser': authUser,
            'X-Youtube-Client-Name': '67',
            'X-Youtube-Client-Version': clientVersion,
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': clientVersion,
                'hl': 'en',
                'gl': 'US',
              },
              'user': <String, dynamic>{},
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw YouTubeMusicSessionException(
        'YTMUSIC_SESSION_REJECTED',
        'YouTube Music rejected this session (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['responseContext'] == null) {
      throw const YouTubeMusicSessionException(
        'YTMUSIC_SESSION_INVALID',
        'YouTube Music returned an invalid account response.',
      );
    }
    final header = _findObject(body, 'activeAccountHeaderRenderer');
    if (header == null) {
      throw const YouTubeMusicSessionException(
        'YTMUSIC_ACCOUNT_UNAVAILABLE',
        'YouTube Music did not return a signed-in account.',
      );
    }
    return _ValidatedAccount(
      displayName: _rendererText(header['accountName']),
      email: _rendererText(header['email']),
    );
  }
}

class _ValidatedAccount {
  const _ValidatedAccount({this.displayName, this.email});

  final String? displayName;
  final String? email;
}

Map<String, dynamic>? _findObject(Object? root, String key) {
  if (root is Map) {
    final direct = root[key];
    if (direct is Map) return Map<String, dynamic>.from(direct);
    for (final value in root.values) {
      final found = _findObject(value, key);
      if (found != null) return found;
    }
  } else if (root is List) {
    for (final value in root) {
      final found = _findObject(value, key);
      if (found != null) return found;
    }
  }
  return null;
}

String? _rendererText(Object? root) {
  if (root is! Map) return null;
  final simple = root['simpleText'];
  if (simple is String && simple.isNotEmpty) return simple;
  final runs = root['runs'];
  if (runs is! List) return null;
  final value = runs
      .whereType<Map>()
      .map((run) => run['text'])
      .whereType<String>()
      .join();
  return value.isEmpty ? null : value;
}

final youtubeMusicSessionProvider = AsyncNotifierProvider<
    YouTubeMusicSessionController, YouTubeMusicConnection>(
  YouTubeMusicSessionController.new,
);
