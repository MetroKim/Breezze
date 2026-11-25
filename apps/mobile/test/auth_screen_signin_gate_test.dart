import 'package:breezze/core/api/breezze_api.dart';
import 'package:breezze/core/auth/auth_session.dart';
import 'package:breezze/features/authentication/auth_screen.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _LocalAuthApi extends BreezzeApi {
  _LocalAuthApi() : super(baseUrl: 'https://breezze.test');

  @override
  Future<Map<String, dynamic>> socialProviders() async =>
      {'apple': false, 'google': false};
}

class _SignedOutSession extends AuthSessionController {
  _SignedOutSession(this.client);
  final BreezzeApi client;

  @override
  AuthState build() => const AuthSignedOut();

  @override
  BreezzeApi get api => client;
}

void main() {
  testWidgets('sign-in gate has no anonymous Browse/Search shortcut',
      (tester) async {
    final api = _LocalAuthApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(() => _SignedOutSession(api)),
      ],
      child: MaterialApp(
        theme: bzLightTheme(),
        home: const AuthScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Browse music'), findsNothing);
    expect(find.text('Continue with email'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
