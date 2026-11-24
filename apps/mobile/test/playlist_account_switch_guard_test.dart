import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/features/library/playlist_detail_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _OtherAccount extends AuthSessionController {
  @override
  AuthState build() => const AuthSignedIn(
    userId: 'account-b',
    email: 'other@example.com',
  );
}

void main() {
  test('playlist owner matches only the active auth state', () {
    const ownerA = AuthSignedIn(
      userId: 'account-a', email: 'owner@example.com',
    );
    const ownerB = AuthSignedIn(
      userId: 'account-b', email: 'other@example.com',
    );
    expect(playlistOwnerMatchesSession('account-a', ownerA), isTrue);
    expect(playlistOwnerMatchesSession('account-a', ownerB), isFalse);
    expect(playlistOwnerMatchesSession('account-a', const AuthSignedOut()),
        isFalse);
    expect(playlistOwnerMatchesSession('account-a', const AuthUninitialized()),
        isFalse);
    expect(playlistOwnerMatchesSession('guest', const AuthSignedOut()), isTrue);
    expect(playlistOwnerMatchesSession('guest', ownerB), isFalse);
  });

  testWidgets('private playlist detail never renders under another account',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(_OtherAccount.new)],
        child: const MaterialApp(
          home: PlaylistDetailScreen(
            ownerId: 'account-a',
            playlistId: '11111111-1111-4111-8111-111111111111',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Playlist unavailable'), findsOneWidget);
    expect(find.text('This playlist is not available in the current account.'),
        findsOneWidget);
    expect(find.text('Add songs'), findsNothing);
  });
}
