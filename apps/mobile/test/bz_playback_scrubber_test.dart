import 'package:breezze/widgets/bz_playback_scrubber.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('tapping mini-player progress commits a seek', (tester) async {
    double? seek;
    await tester.pumpWidget(MaterialApp(
      theme: bzDarkTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: BzPlaybackScrubber(
              progress: 0.2,
              enabled: true,
              onSeek: (value) => seek = value,
            ),
          ),
        ),
      ),
    ));
    final bounds = tester.getRect(find.byType(BzPlaybackScrubber));
    expect(bounds.height, greaterThanOrEqualTo(44));
    await tester.tapAt(Offset(bounds.left + bounds.width * 0.75,
        bounds.center.dy));
    await tester.pump();
    expect(seek, closeTo(0.75, 0.02));
  });

  testWidgets('disabled scrubber never seeks', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      theme: bzLightTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: BzPlaybackScrubber(
              progress: 0.1,
              enabled: false,
              onSeek: (_) => calls++,
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(BzPlaybackScrubber));
    await tester.pump();
    expect(calls, 0);
  });
}
