import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, SignOutScope;

import '../api/breezze_api.dart';
import 'supabase_auth_bridge.dart';
import '../../features/player/player_controller.dart';

/// Auth session state — what the UI renders.
sealed class AuthState {
  const AuthState();
}

class AuthUninitialized extends AuthState {
  const AuthUninitialized();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

class AuthSigningIn extends AuthState {
  final bool social;
  const AuthSigningIn({this.social = false});
}

class AuthSignedIn extends AuthState {
  final String userId;
  final String email;
  const AuthSignedIn({required this.userId, required this.email});
}

class AuthMfaRequired extends AuthState {
  final String userId;
  final String email;
  final bool setupRequired;
  final String? secret;
  final String? provisioningUri;

  const AuthMfaRequired({
    required this.userId,
    required this.email,
    required this.setupRequired,
    this.secret,
    this.provisioningUri,
  });
}

class AuthMfaRecoveryCodes extends AuthState {
  final String userId;
  final String email;
  final List<String> codes;

  const AuthMfaRecoveryCodes({
    required this.userId,
    required this.email,
    required this.codes,
  });
}

/// Only a signed-in, email-confirmed Supabase identity can reach this step.
/// A separate old Breezze password proves ownership of existing music data.
class AuthLegacyLinkRequired extends AuthState {
  final String? errorCode;
  const AuthLegacyLinkRequired({this.errorCode});
}

class AuthLegacyLinking extends AuthState {
  const AuthLegacyLinking();
}

class AuthError extends AuthState {
  final String code;
  const AuthError(this.code);
}

/// Session controller: access tokens remain memory-only; refresh tokens use
/// iOS Keychain / Android Keystore-backed secure storage.
class AuthSessionController extends Notifier<AuthState> {
  Future<bool>? _refreshInFlight;
  int _socialAttempt = 0;
  static const _refreshTokenKey = 'breezze.refresh_token';
  static const _secureStorage = FlutterSecureStorage();

  static const _configuredApiUrl = String.fromEnvironment('BREEZZE_API_URL');
  static const _productionApiUrl =
      'https://breezze-api-edge.ykw8vmq7ph.workers.dev';

  late final BreezzeApi _api = BreezzeApi(
    baseUrl: _configuredApiUrl.isNotEmpty
        ? _configuredApiUrl
        : (kReleaseMode ? _productionApiUrl : 'http://localhost:3000'),
  )..onUnauthorized = _refreshAccessToken;

  @override
  AuthState build() {
    return const AuthUninitialized();
  }

  BreezzeApi get api => _api;

  Future<bool> _refreshAccessToken() async {
    final active = _refreshInFlight;
    if (active != null) return active;
    final pending = _performRefresh();
    _refreshInFlight = pending;
    try {
      return await pending;
    } finally {
      _refreshInFlight = null;
    }
  }

  /// Every API reauthorization in Supabase mode requires a live Supabase
  /// session. Never extend the legacy refresh-token family after Supabase
  /// has been signed out or its session has expired.
  Future<bool> _performRefresh() async {
    try {
      if (SupabaseAuthBridge.enabled) {
        final session = await SupabaseAuthBridge.client.auth.refreshSession();
        final token = session.session?.accessToken;
        if (token == null || token.isEmpty) {
          throw StateError('SUPABASE_SESSION_EXPIRED');
        }
        await _exchangeSupabaseSession(token);
        return true;
      }

      final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (refreshToken == null || refreshToken.isEmpty) return false;
      final response = await _api.refresh(refreshToken);
      await _persistSession(response);
      return true;
    } catch (_) {
      _api.accessToken = null;
      try {
        await _secureStorage.delete(key: _refreshTokenKey);
      } catch (_) {}
      state = const AuthSignedOut();
      return false;
    }
  }

  Future<void> restoreSession() async {
    try {
      if (SupabaseAuthBridge.enabled) {
        final current = SupabaseAuthBridge.client.auth.currentSession;
        if (current == null) {
          _api.accessToken = null;
          await _secureStorage.delete(key: _refreshTokenKey);
          state = const AuthSignedOut();
          return;
        }
        final session = current.isExpired
            ? (await SupabaseAuthBridge.client.auth.refreshSession()).session
            : current;
        if (session == null) {
          throw StateError('SUPABASE_SESSION_EXPIRED');
        }
        await _exchangeSupabaseSession(session.accessToken);
        return;
      }

      final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (refreshToken == null || refreshToken.isEmpty) {
        state = const AuthSignedOut();
        return;
      }
      final response = await _api.refresh(refreshToken);
      await _persistSession(response);
    } on BreezzeApiException catch (error) {
      _api.accessToken = null;
      try {
        await _secureStorage.delete(key: _refreshTokenKey);
      } catch (_) {}
      if (SupabaseAuthBridge.enabled &&
          error.code == 'LEGACY_ACCOUNT_LINK_REQUIRED') {
        // Keep the verified Supabase identity so the user can prove
        // ownership of their existing Breezze library.
        state = const AuthLegacyLinkRequired();
      } else {
        state = const AuthSignedOut();
      }
    } catch (_) {
      _api.accessToken = null;
      try {
        await _secureStorage.delete(key: _refreshTokenKey);
      } catch (_) {}
      state = const AuthSignedOut();
    }
  }

  Future<void> _exchangeSupabaseSession(
    String accessToken, {
    int? expectedSocialAttempt,
  }) async {
    if (expectedSocialAttempt != null &&
        expectedSocialAttempt != _socialAttempt) return;
    final previousRefreshToken =
        await _secureStorage.read(key: _refreshTokenKey);
    final response = await _api.exchangeSupabaseAccessToken(accessToken);

    // Do not persist an exchange that was canceled while the network request
    // was in flight. Revoke its newly issued Breezze session instead.
    if (expectedSocialAttempt != null &&
        expectedSocialAttempt != _socialAttempt) {
      try {
        await _api.logout(response.refreshToken);
      } catch (_) {}
      return;
    }

    await _persistSession(response);

    // Secure storage writes are asynchronous too: cancellation or switching
    // accounts may happen after the first guard and before this point.
    if (expectedSocialAttempt != null &&
        expectedSocialAttempt != _socialAttempt) {
      if (_api.accessToken == response.accessToken) {
        _api.accessToken = null;
        try {
          await _secureStorage.delete(key: _refreshTokenKey);
        } catch (_) {}
        state = const AuthSignedOut();
      }
      try {
        await _api.logout(response.refreshToken);
      } catch (_) {}
      return;
    }

    // Rotating the mapped Breezze family avoids accumulating live legacy
    // sessions on every app restart or Supabase refresh.
    if (previousRefreshToken != null &&
        previousRefreshToken != response.refreshToken) {
      try {
        await _api.logout(previousRefreshToken);
      } catch (_) {
        // Expired or unreachable old sessions are never used as a fallback.
      }
    }
  }

  Future<void> _persistSession(AuthResponse response) async {
    await _secureStorage.write(key: _refreshTokenKey, value: response.refreshToken);
    _api.accessToken = response.accessToken;
    if (response.mfaRequired) {
      state = AuthMfaRequired(
        userId: response.userId,
        email: response.email,
        setupRequired: response.mfaSetupRequired,
      );
    } else {
      state = AuthSignedIn(userId: response.userId, email: response.email);
    }
  }

  Future<void> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    state = const AuthSigningIn();
    try {
      if (SupabaseAuthBridge.enabled) {
        final response = await SupabaseAuthBridge.client.auth.signUp(
          email: email,
          password: password,
          data: displayName == null ? null : {'full_name': displayName},
        );
        // Email verification may be required. Never issue a Breezze session
        // until the identity authority returns a signed-in session.
        final session = response.session;
        if (session == null) {
          state = const AuthError('EMAIL_VERIFICATION_REQUIRED');
          return;
        }
        await _exchangeSupabaseSession(session.accessToken);
      } else {
        final response = await _api.register(
          email,
          password,
          displayName: displayName,
        );
        await _persistSession(response);
      }
    } on BreezzeApiException catch (e) {
      if (SupabaseAuthBridge.enabled && e.code == 'LEGACY_ACCOUNT_LINK_REQUIRED') {
        state = const AuthLegacyLinkRequired();
      } else {
        state = AuthError(e.code);
      }
    } on AuthException {
      state = const AuthError('SUPABASE_AUTH_FAILED');
    } catch (_) {
      state = const AuthError('NETWORK_ERROR');
    }
  }

  Future<void> login(String email, String password) async {
    state = const AuthSigningIn();
    try {
      if (SupabaseAuthBridge.enabled) {
        final response = await SupabaseAuthBridge.client.auth
            .signInWithPassword(email: email, password: password);
        final session = response.session;
        if (session == null) {
          state = const AuthError('SUPABASE_AUTH_FAILED');
          return;
        }
        await _exchangeSupabaseSession(session.accessToken);
      } else {
        final response = await _api.login(email, password);
        await _persistSession(response);
      }
    } on BreezzeApiException catch (e) {
      if (SupabaseAuthBridge.enabled && e.code == 'LEGACY_ACCOUNT_LINK_REQUIRED') {
        state = const AuthLegacyLinkRequired();
      } else {
        state = AuthError(e.code);
      }
    } on AuthException {
      state = const AuthError('INVALID_CREDENTIALS');
    } catch (_) {
      state = const AuthError('NETWORK_ERROR');
    }
  }

  Future<void> socialLogin(
    String provider, {
    Map<String, dynamic>? preparedFlow,
  }) async {
    if (SupabaseAuthBridge.enabled) {
      await _signInWithNativeSupabase(provider);
      return;
    }
    final attempt = ++_socialAttempt;
    state = const AuthSigningIn(social: true);
    try {
      // Preloaded flow keeps launchUrl on the original pointer activation
      // for browsers that block asynchronous popups.
      final flow = preparedFlow ?? await _api.startSocialLogin(provider);
      if (attempt != _socialAttempt) return;
      final flowId = flow['id'];
      final pollSecret = flow['secret'];
      final authorizationUrl = Uri.tryParse(flow['authorizationUrl'] as String? ?? '');
      if (flowId is! String || pollSecret is! String ||
          authorizationUrl == null || authorizationUrl.scheme != 'https') {
        throw const BreezzeApiException(
          code: 'SOCIAL_FLOW_INVALID',
          message: 'The sign-in provider returned an invalid authorization URL.',
        );
      }
      if (!await launchUrl(authorizationUrl, mode: LaunchMode.externalApplication)) {
        throw const BreezzeApiException(
          code: 'SOCIAL_BROWSER_UNAVAILABLE',
          message: 'Cannot open the secure system browser for sign-in.',
        );
      }
      // The system browser never sees Breezze refresh tokens. The app
      // redeems a single-use random pairing secret through the own backend.
      for (var n = 0; n < 150; n++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (attempt != _socialAttempt) return;
        final result = await _api.pollSocialLogin(flowId: flowId, secret: pollSecret);
        if (attempt != _socialAttempt) return;
        if (result['status'] == 'pending') continue;
        if (result['status'] == 'completed' && result['session'] is Map) {
          final session = AuthResponse.fromJson(
            Map<String, dynamic>.from(result['session'] as Map),
          );
          if (attempt != _socialAttempt) return;
          await _persistSession(session);
          return;
        }
        throw BreezzeApiException(
          code: result['code'] as String? ?? 'SOCIAL_AUTH_FAILED',
          message: 'The identity provider could not complete the sign-in.',
        );
      }
      throw const BreezzeApiException(
        code: 'SOCIAL_AUTH_EXPIRED',
        message: 'The browser sign-in timed out. You can try again.',
      );
    } on BreezzeApiException catch (e) {
      if (attempt == _socialAttempt) state = AuthError(e.code);
    } catch (_) {
      if (attempt == _socialAttempt) state = const AuthError('SOCIAL_AUTH_FAILED');
    }
  }

  /// Native social identity is verified by Supabase before Breezze sees a
  /// short-lived access token. A failed exchange never leaves a half-signed-in
  /// Supabase session that could later impersonate another Breezze account.
  Future<void> _signInWithNativeSupabase(String provider) async {
    if (!SupabaseAuthBridge.readyFor(provider)) {
      state = const AuthError('SOCIAL_PROVIDER_NOT_CONFIGURED');
      return;
    }
    final attempt = ++_socialAttempt;
    state = const AuthSigningIn(social: true);
    try {
      final token = provider == 'google'
          ? await SupabaseAuthBridge.signInWithNativeGoogle()
          : await SupabaseAuthBridge.signInWithNativeApple();

      if (attempt != _socialAttempt) {
        // Avoid affecting a newer sign-in that may already be in progress.
        if (state is AuthSignedOut) {
          await SupabaseAuthBridge.client.auth.signOut(
            scope: SignOutScope.local,
          );
        }
        return;
      }
      await _exchangeSupabaseSession(
        token,
        expectedSocialAttempt: attempt,
      );
    } on NativeSocialLoginCancelled {
      if (attempt == _socialAttempt) state = const AuthSignedOut();
    } on BreezzeApiException catch (error) {
      if (attempt != _socialAttempt) return;
      if (error.code == 'LEGACY_ACCOUNT_LINK_REQUIRED') {
        // Keep the verified Supabase identity for explicit old-account proof.
        state = const AuthLegacyLinkRequired();
        return;
      }
      try {
        await SupabaseAuthBridge.client.auth.signOut(
          scope: SignOutScope.local,
        );
      } catch (_) {}
      state = AuthError(error.code);
    } catch (_) {
      if (attempt != _socialAttempt) return;
      try {
        await SupabaseAuthBridge.client.auth.signOut(
          scope: SignOutScope.local,
        );
      } catch (_) {}
      state = const AuthError('SOCIAL_AUTH_FAILED');
    }
  }

  void cancelSocialLogin() {
    ++_socialAttempt;
    if (state is AuthSigningIn) state = const AuthSignedOut();
  }

  /// Link once without copying or reassigning existing Breezze music data.
  /// The old password is submitted only to our HTTPS backend, and is never
  /// persisted or forwarded to Supabase.
  Future<void> linkLegacyAccount(String legacyEmail, String legacyPassword) async {
    if (!SupabaseAuthBridge.enabled) {
      state = const AuthError('SUPABASE_AUTH_NOT_CONFIGURED');
      return;
    }
    state = const AuthLegacyLinking();
    try {
      final auth = SupabaseAuthBridge.client.auth;
      var session = auth.currentSession;
      if (session == null || session.isExpired) {
        session = (await auth.refreshSession()).session;
      }
      if (session == null || session.accessToken.isEmpty) {
        state = const AuthLegacyLinkRequired(
          errorCode: 'SUPABASE_SESSION_EXPIRED',
        );
        return;
      }
      final response = await _api.linkLegacySupabaseAccount(
        supabaseAccessToken: session.accessToken,
        legacyEmail: legacyEmail,
        legacyPassword: legacyPassword,
      );
      await _persistSession(response);
    } on BreezzeApiException catch (error) {
      state = AuthLegacyLinkRequired(errorCode: error.code);
    } on AuthException {
      state = const AuthLegacyLinkRequired(errorCode: 'SUPABASE_SESSION_EXPIRED');
    } catch (_) {
      state = const AuthLegacyLinkRequired(errorCode: 'NETWORK_ERROR');
    }
  }

  Future<void> cancelLegacyLink() async {
    if (!SupabaseAuthBridge.enabled) return;
    ++_socialAttempt;
    _api.accessToken = null;
    try {
      await SupabaseAuthBridge.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    state = const AuthSignedOut();
  }

  Future<void> beginMfaSetup(String password) async {
    final current = state;
    if (current is! AuthMfaRequired || !current.setupRequired) return;
    final result = await _api.beginMfaSetup(password);
    state = AuthMfaRequired(
      userId: current.userId,
      email: current.email,
      setupRequired: true,
      secret: result['secret'] as String?,
      provisioningUri: result['provisioningUri'] as String?,
    );
  }

  Future<void> verifyMfaSetup(String code) async {
    final current = state;
    if (current is! AuthMfaRequired || !current.setupRequired) return;
    final result = await _api.verifyMfaSetup(code);
    final token = result['accessToken'];
    if (token is! String || token.isEmpty) {
      throw const BreezzeApiException(code: 'MFA_TOKEN_MISSING', message: 'MFA verification did not return a session token');
    }
    _api.accessToken = token;
    final codes = (result['recoveryCodes'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    state = AuthMfaRecoveryCodes(
      userId: current.userId,
      email: current.email,
      codes: codes,
    );
  }

  Future<void> verifyMfa(String code) async {
    final current = state;
    if (current is! AuthMfaRequired || current.setupRequired) return;
    final result = await _api.verifyMfa(code);
    final token = result['accessToken'];
    if (token is! String || token.isEmpty) {
      throw const BreezzeApiException(code: 'MFA_TOKEN_MISSING', message: 'MFA verification did not return a session token');
    }
    _api.accessToken = token;
    state = AuthSignedIn(userId: current.userId, email: current.email);
  }

  void completeMfaEnrollment() {
    final current = state;
    if (current is AuthMfaRecoveryCodes) {
      state = AuthSignedIn(userId: current.userId, email: current.email);
    }
  }

  Future<void> signOut() async {
    ++_socialAttempt;
    // Stop the global player while the access token is still valid so its
    // server-authorized playback session is closed before account logout.
    try {
      await ref.read(playerControllerProvider.notifier).stop();
    } catch (_) {}
    String? refreshToken;
    try {
      refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    } catch (_) {}
    if (refreshToken != null) {
      try {
        await _api.logout(refreshToken);
      } catch (_) {
        // Local logout must still complete when the network is unavailable.
      }
    }
    if (SupabaseAuthBridge.enabled) {
      await SupabaseAuthBridge.signOutNativeGoogle();
      try {
        await SupabaseAuthBridge.client.auth.signOut();
      } catch (_) {
        // If the server is unreachable, clear the local SDK session anyway.
        try {
          await SupabaseAuthBridge.client.auth.signOut(
            scope: SignOutScope.local,
          );
        } catch (_) {}
      }
    }
    _api.accessToken = null;
    try {
      await _secureStorage.delete(key: _refreshTokenKey);
    } catch (_) {}
    state = const AuthSignedOut();
  }
}

final authSessionProvider =
    NotifierProvider<AuthSessionController, AuthState>(
  AuthSessionController.new,
);
