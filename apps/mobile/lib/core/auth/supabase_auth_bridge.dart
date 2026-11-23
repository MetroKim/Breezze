import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Deliberate cancellation of the native provider sheet.
class NativeSocialLoginCancelled implements Exception {
  const NativeSocialLoginCancelled();
}

/// Supabase owns passwords and social identity. The Breezze backend exchanges
/// a VERIFIED Supabase access token for a transitional API session; no social
/// provider credential is sent to Breezze or stored by its Flutter client.
///
/// Keep Google/Apple disabled until their native platform configuration and
/// Supabase provider registration are complete. There is no browser fallback.
class SupabaseAuthBridge {
  const SupabaseAuthBridge._();

  static const url = String.fromEnvironment('BREEZZE_SUPABASE_URL');
  static const publishableKey =
      String.fromEnvironment('BREEZZE_SUPABASE_PUBLISHABLE_KEY');
  static const googleWebClientId =
      String.fromEnvironment('BREEZZE_GOOGLE_WEB_CLIENT_ID');
  static const googleIosClientId =
      String.fromEnvironment('BREEZZE_GOOGLE_IOS_CLIENT_ID');
  static const appleNativeEnabled =
      bool.fromEnvironment('BREEZZE_APPLE_NATIVE_ENABLED');

  static Future<void>? _googleInitialization;

  static bool get enabled => url.isNotEmpty && publishableKey.isNotEmpty;

  static bool _validGoogleClientId(String id) =>
      id.length > '.apps.googleusercontent.com'.length &&
      id.endsWith('.apps.googleusercontent.com') &&
      !id.contains(RegExp(r'\s'));

  /// Shared with tests: platform checks never invoke native plugins.
  static bool canUseNativeGoogle({
    required TargetPlatform platform,
    required bool web,
    required String webClientId,
    required String iosClientId,
  }) =>
      !web &&
      _validGoogleClientId(webClientId) &&
      (platform == TargetPlatform.android ||
          (platform == TargetPlatform.iOS &&
              _validGoogleClientId(iosClientId)));

  static bool canUseNativeApple({
    required TargetPlatform platform,
    required bool web,
    required bool capabilityEnabled,
  }) =>
      !web &&
      capabilityEnabled &&
      platform == TargetPlatform.iOS;

  static bool get nativeGoogleReady =>
      enabled &&
      canUseNativeGoogle(
        platform: defaultTargetPlatform,
        web: kIsWeb,
        webClientId: googleWebClientId,
        iosClientId: googleIosClientId,
      );

  static bool get nativeAppleReady =>
      enabled &&
      canUseNativeApple(
        platform: defaultTargetPlatform,
        web: kIsWeb,
        capabilityEnabled: appleNativeEnabled,
      );

  static bool readyFor(String provider) => switch (provider) {
        'google' => nativeGoogleReady,
        'apple' => nativeAppleReady,
        _ => false,
      };

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

  /// Google 7.x native account picker: Android and iOS only. Supabase
  /// independently verifies the Google ID token and issues its own session.
  static Future<String> signInWithNativeGoogle() async {
    if (!nativeGoogleReady) {
      throw StateError('GOOGLE_NATIVE_SIGN_IN_NOT_CONFIGURED');
    }
    final google = GoogleSignIn.instance;
    _googleInitialization ??= google.initialize(
      clientId:
          defaultTargetPlatform == TargetPlatform.iOS ? googleIosClientId : null,
      serverClientId: googleWebClientId,
    );
    await _googleInitialization;

    late final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const NativeSocialLoginCancelled();
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('GOOGLE_ID_TOKEN_MISSING');
    }
    final response = await client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    final token = response.session?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('GOOGLE_SUPABASE_SESSION_MISSING');
    }
    return token;
  }

  static String hashAppleNonce(String rawNonce) =>
      sha256.convert(utf8.encode(rawNonce)).toString();

  /// iOS native Apple authorization sheet, with a per-attempt SHA256 nonce.
  /// Android/web Apple OAuth is intentionally not used (browser flow).
  static Future<String> signInWithNativeApple() async {
    if (!nativeAppleReady) {
      throw StateError('APPLE_NATIVE_SIGN_IN_NOT_CONFIGURED');
    }
    final rawNonce = client.auth.generateRawNonce();

    late final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashAppleNonce(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const NativeSocialLoginCancelled();
      }
      rethrow;
    }

    final idToken = credential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('APPLE_ID_TOKEN_MISSING');
    }
    final response = await client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    final token = response.session?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('APPLE_SUPABASE_SESSION_MISSING');
    }

    // Apple discloses the full name only during the first authorization.
    // Preserve it best-effort; never make a valid sign-in fail if the
    // optional profile write is temporarily unavailable.
    final fullName = [
      credential.givenName?.trim() ?? '',
      credential.familyName?.trim() ?? '',
    ].where((name) => name.isNotEmpty).join(' ');
    final user = response.user;
    if (fullName.isNotEmpty && user != null) {
      final safeName = fullName.length > 80
          ? fullName.substring(0, 80)
          : fullName;
      try {
        await client.auth.updateUser(
          UserAttributes(data: {'full_name': safeName}),
        );
        final profile = await client
            .from('profiles')
            .select('display_name')
            .eq('id', user.id)
            .maybeSingle();
        if (profile != null && profile['display_name'] == null) {
          await client.from('profiles').update({
            'display_name': safeName,
          }).eq('id', user.id);
        }
      } catch (_) {
        // Account authentication is independent of optional profile details.
      }
    }
    return token;
  }

  static Future<void> signOutNativeGoogle() async {
    if (!nativeGoogleReady || _googleInitialization == null) return;
    try {
      await _googleInitialization;
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Supabase session revocation is the authoritative sign-out.
    }
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
