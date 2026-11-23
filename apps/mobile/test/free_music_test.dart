import 'package:breezze/app/bootstrap.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';
import 'package:breezze/features/free_music/open_goldberg.dart';
import 'package:breezze/features/player/player_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the open album resolves without a signed-in user or Breezze API', () async {
    final container = ProviderContainer(overrides: [
      playbackResolverProvider.overrideWith((ref) => LiveResolver(ref)),
    ]);
    addTearDown(container.dispose);
    final resolver = container.read(playbackResolverProvider);
    final urls = <String>{};
    for (var i = 0; i < OpenGoldberg.length; i++) {
      final id = OpenGoldberg.id(i);
      expect(canQueueTrackId(id), isTrue);
      final source = await resolver.resolve(TrackInfo(id: id));
      expect(source?.codec, 'mp3');
      expect(source?.sessionId, isNull);
      expect(Uri.parse(source!.streamUrl).host, 'archive.org');
      urls.add(source.streamUrl);
    }
    expect(urls.length, 32);
    expect(OpenGoldberg.audio('bz:open_goldberg:33'), isNull);
    expect(OpenGoldberg.audio('bz:open_goldberg:01'), isNull);
  });
}
