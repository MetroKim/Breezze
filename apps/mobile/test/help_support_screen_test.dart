import 'package:breezze/features/settings/help_support_screen.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Help Centre exposes honest playback and catalog guidance',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: bzLightTheme(),
          home: const HelpSupportScreen(),
        ),
      ),
    );

    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('Why can I find a song but not play it?'), findsOneWidget);
    expect(find.text('Why are some Browse collections empty?'), findsOneWidget);
    await tester.tap(find.text('Why can I find a song but not play it?'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Playback starts only after the backend confirms'),
      findsOneWidget,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Contact Breezze Support'), findsOneWidget);
    expect(
      find.text('Sign in to submit a support request and view your request history.'),
      findsOneWidget,
    );
  });
}
