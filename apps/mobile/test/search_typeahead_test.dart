import 'dart:async';

import 'package:breezze/app/bootstrap.dart';
import 'package:breezze/features/search/search_screen.dart';
import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class _SearchSource implements ProviderAdapter {
  final calls = <String>[];
  final pending = <String, Completer<ProviderOp<List<ProviderTrack>>>>{};

  @override
  String get providerId => 'test';

  @override
  String get adapterVersion => '1';

  @override
  Future<ProviderOp<List<ProviderTrack>>> search(String query) {
    calls.add(query);
    final result = Completer<ProviderOp<List<ProviderTrack>>>();
    pending[query] = result;
    return result.future;
  }

  @override
  Future<ProviderOp<ProviderTrack>> getTrack(String providerTrackId) async =>
      ProviderUnsupported('Not used by this test');
}

ProviderOp<List<ProviderTrack>> _result(String title) => ProviderOk([
      ProviderTrack(
        breezzeTrackId: 'bz:youtube_music:abcdefghijk',
        providerTrackId: 'abcdefghijk',
        title: title,
        artist: 'Artist',
        duration: const Duration(minutes: 3),
      ),
    ]);

void main() {
  testWidgets('typeahead debounces and discards older results', (tester) async {
    final source = _SearchSource();
    await tester.pumpWidget(ProviderScope(
      overrides: [catalogSourceProvider.overrideWithValue(source)],
      child: MaterialApp(theme: bzLightTheme(), home: const Scaffold(body: SearchScreen())),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 499));
    expect(source.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(source.calls, ['old']);

    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 500));
    expect(source.calls, ['old', 'new']);
    source.pending['old']!.complete(_result('Old result'));
    await tester.pump();
    expect(find.text('Old result'), findsNothing);
    source.pending['new']!.complete(_result('New result'));
    await tester.pump();
    expect(find.text('New result'), findsOneWidget);
  });
}
