import 'package:breezze/app/downloads_controller.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SwitchableSession extends AuthSessionController {
  @override
  AuthState build() =>
      const AuthSignedIn(userId: 'listener-a', email: 'a@example.test');

  void switchTo(String userId) {
    state = AuthSignedIn(userId: userId, email: '$userId@example.test');
  }

  void signOutForTest() => state = const AuthSignedOut();
}

void main() {
  test('download status from listener A is cleared when listener B signs in',
      () async {
    final container = ProviderContainer(
      overrides: [
        authSessionProvider.overrideWith(_SwitchableSession.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(downloadProgressProvider.notifier);
    final session =
        container.read(authSessionProvider.notifier) as _SwitchableSession;
    container.read(downloadJobStatusProvider.notifier).state = const {
      'catalog-private-a': 'downloading',
    };
    expect(container.read(downloadJobStatusProvider), contains('catalog-private-a'));

    session.switchTo('listener-b');
    expect(container.read(downloadJobStatusProvider), isEmpty);
    expect(container.read(downloadProgressProvider), isEmpty);

    session.signOutForTest();
    expect(container.read(downloadJobStatusProvider), isEmpty);
  });
}
