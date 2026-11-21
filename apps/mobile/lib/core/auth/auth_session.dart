import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/breezze_api.dart';

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
  const AuthSigningIn();
}

class AuthSignedIn extends AuthState {
  final String userId;
  final String email;
  const AuthSignedIn({required this.userId, required this.email});
}

class AuthError extends AuthState {
  final String code;
  const AuthError(this.code);
}

/// Session controller: access tokens remain memory-only; refresh tokens use
/// iOS Keychain / Android Keystore-backed secure storage.
class AuthSessionController extends Notifier<AuthState> {
  static const _refreshTokenKey = 'breezze.refresh_token';
  static const _secureStorage = FlutterSecureStorage();

  late final BreezzeApi _api = BreezzeApi(
    baseUrl: const String.fromEnvironment(
      'BREEZZE_API_URL',
      defaultValue: 'http://localhost:3000',
    ),
  );

  @override
  AuthState build() {
    return const AuthUninitialized();
  }

  BreezzeApi get api => _api;

  Future<void> restoreSession() async {
    try {
      final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
      if (refreshToken == null || refreshToken.isEmpty) {
        state = const AuthSignedOut();
        return;
      }
      final response = await _api.refresh(refreshToken);
      await _persistSession(response);
    } catch (_) {
      _api.accessToken = null;
      await _secureStorage.delete(key: _refreshTokenKey);
      state = const AuthSignedOut();
    }
  }

  Future<void> _persistSession(AuthResponse response) async {
    await _secureStorage.write(key: _refreshTokenKey, value: response.refreshToken);
    _api.accessToken = response.accessToken;
    state = AuthSignedIn(userId: response.userId, email: response.email);
  }

  Future<void> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    state = const AuthSigningIn();
    try {
      final response = await _api.register(email, password,
          displayName: displayName);
      await _persistSession(response);
    } on BreezzeApiException catch (e) {
      state = AuthError(e.code);
    } catch (_) {
      state = const AuthError('NETWORK_ERROR');
    }
  }

  Future<void> login(String email, String password) async {
    state = const AuthSigningIn();
    try {
      final response = await _api.login(email, password);
      await _persistSession(response);
    } on BreezzeApiException catch (e) {
      state = AuthError(e.code);
    } catch (_) {
      state = const AuthError('NETWORK_ERROR');
    }
  }

  Future<void> signOut() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken != null) {
      try {
        await _api.logout(refreshToken);
      } catch (_) {
        // Local logout must still complete when the network is unavailable.
      }
    }
    _api.accessToken = null;
    await _secureStorage.delete(key: _refreshTokenKey);
    state = const AuthSignedOut();
  }
}

final authSessionProvider =
    NotifierProvider<AuthSessionController, AuthState>(
  AuthSessionController.new,
);
