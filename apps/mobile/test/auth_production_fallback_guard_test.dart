import 'package:breezze/core/auth/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release builds never use legacy Breezze login with missing Supabase', () {
    expect(
      AuthSessionController.legacyAuthAllowedForBuild(
        releaseMode: true,
        supabaseConfigured: false,
      ),
      isFalse,
    );
  });

  test('release builds must not downgrade from configured Supabase', () {
    expect(
      AuthSessionController.legacyAuthAllowedForBuild(
        releaseMode: true,
        supabaseConfigured: true,
      ),
      isFalse,
    );
  });

  test('debug builds retain legacy-only migration testing when unconfigured', () {
    expect(
      AuthSessionController.legacyAuthAllowedForBuild(
        releaseMode: false,
        supabaseConfigured: false,
      ),
      isTrue,
    );
  });

  test('debug builds prefer configured Supabase instead of old login', () {
    expect(
      AuthSessionController.legacyAuthAllowedForBuild(
        releaseMode: false,
        supabaseConfigured: true,
      ),
      isFalse,
    );
  });
}
