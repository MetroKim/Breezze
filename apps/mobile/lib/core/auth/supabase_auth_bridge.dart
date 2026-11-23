import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase owns credentials and social identities. Breezze only exchanges
/// verified access tokens for temporary compatibility with its existing API.
///
/// Activation is explicit and build-time configured; a partial configuration
/// fails closed instead of silently sending a user's password to legacy auth.
class SupabaseAuthBridge {
  const SupabaseAuthBridge._();

  static const url = String.fromEnvironment('BREEZZE_SUPABASE_URL');
  static const publishableKey =
      String.fromEnvironment('BREEZZE_SUPABASE_PUBLISHABLE_KEY');

  static bool get enabled => url.isNotEmpty && publishableKey.isNotEmpty;

  static Future<void> initialize() async {
    if (url.isEmpty && publishableKey.isEmpty) return;
    if (!enabled) {
      throw StateError(
        'Supabase Auth requires BREEZZE_SUPABASE_URL and '
        'BREEZZE_SUPABASE_PUBLISHABLE_KEY together.',
      );
    }
    await Supabase.initialize(
      url: url,
      publishableKey: publishableKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: _BreezzeSupabaseSecureStorage(),
      ),
    );
  }

  static SupabaseClient get client {
    if (!enabled) {
      throw StateError('Supabase Auth has not been configured.');
    }
    return Supabase.instance.client;
  }
}

/// Keep the Supabase session out of ordinary shared preferences.
/// Uses the platform-backed keychain/keystore storage implementation.
class _BreezzeSupabaseSecureStorage extends LocalStorage {
  static const _storage = FlutterSecureStorage();
  static const _key = 'breezze.supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
