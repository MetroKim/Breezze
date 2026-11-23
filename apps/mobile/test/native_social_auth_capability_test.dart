import 'package:breezze/core/auth/supabase_auth_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const webClientId = '123-web.apps.googleusercontent.com';
  const iosClientId = '456-ios.apps.googleusercontent.com';

  test('Google native sign-in requires the Web OAuth client ID', () {
    expect(SupabaseAuthBridge.canUseNativeGoogle(
      platform: TargetPlatform.android,
      web: false,
      webClientId: '',
      iosClientId: '',
    ), isFalse);
    expect(SupabaseAuthBridge.canUseNativeGoogle(
      platform: TargetPlatform.android,
      web: false,
      webClientId: webClientId,
      iosClientId: '',
    ), isTrue);
  });

  test('Google iOS requires a separate registered iOS client ID', () {
    expect(SupabaseAuthBridge.canUseNativeGoogle(
      platform: TargetPlatform.iOS,
      web: false,
      webClientId: webClientId,
      iosClientId: '',
    ), isFalse);
    expect(SupabaseAuthBridge.canUseNativeGoogle(
      platform: TargetPlatform.iOS,
      web: false,
      webClientId: webClientId,
      iosClientId: iosClientId,
    ), isTrue);
  });

  test('Google native flow is not exposed on web or unsupported desktops', () {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      expect(SupabaseAuthBridge.canUseNativeGoogle(
        platform: platform,
        web: true,
        webClientId: webClientId,
        iosClientId: iosClientId,
      ), isFalse);
    }
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      expect(SupabaseAuthBridge.canUseNativeGoogle(
        platform: platform,
        web: false,
        webClientId: webClientId,
        iosClientId: iosClientId,
      ), isFalse);
    }
  });

  test('Google client IDs must have the correct provider suffix', () {
    expect(SupabaseAuthBridge.canUseNativeGoogle(
      platform: TargetPlatform.android,
      web: false,
      webClientId: 'not-a-google-client-id',
      iosClientId: iosClientId,
    ), isFalse);
  });

  test('Apple native sheet is iOS-only and capability-gated', () {
    expect(SupabaseAuthBridge.canUseNativeApple(
      platform: TargetPlatform.iOS,
      web: false,
      capabilityEnabled: true,
    ), isTrue);
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ]) {
      expect(SupabaseAuthBridge.canUseNativeApple(
        platform: platform,
        web: false,
        capabilityEnabled: true,
      ), isFalse);
    }
    expect(SupabaseAuthBridge.canUseNativeApple(
      platform: TargetPlatform.iOS,
      web: true,
      capabilityEnabled: true,
    ), isFalse);
    expect(SupabaseAuthBridge.canUseNativeApple(
      platform: TargetPlatform.iOS,
      web: false,
      capabilityEnabled: false,
    ), isFalse);
  });

  test('Apple nonce is SHA-256 hashed before passing to the OS sheet', () {
    expect(
      SupabaseAuthBridge.hashAppleNonce('example'),
      '50d858e0985ecc7f60418aaf0cc5ab587f42c2570a884095a9e8ccacd0f6545c',
    );
  });

  test('unconfigured build never exposes a native sign-in provider', () {
    expect(SupabaseAuthBridge.readyFor('unknown'), isFalse);
  });
}
