import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/youtube_player_handoff.dart';

void main() {
  test('only valid YouTube video IDs are accepted', () {
    expect(YoutubePlayerHandoff.isValidProviderTrackId('dQw4w9WgXcQ'), isTrue);
    expect(YoutubePlayerHandoff.isValidProviderTrackId('aBc123-_xYz'), isTrue);
    for (final invalid in [
      '',
      'too-short',
      'abcdefghijklmnopqrstuvwxyz',
      '../etc/passwd',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'dQw4w9WgXcQ&autoplay=1',
    ]) {
      expect(YoutubePlayerHandoff.isValidProviderTrackId(invalid), isFalse,
          reason: invalid);
    }
  });

  test('official YouTube Music handoff uses an exact safe watch URL', () {
    final uri = YoutubePlayerHandoff.officialMusicUri('dQw4w9WgXcQ');
    expect(uri.scheme, 'https');
    expect(uri.host, 'music.youtube.com');
    expect(uri.path, '/watch');
    expect(uri.queryParameters, {'v': 'dQw4w9WgXcQ'});
    expect(() => YoutubePlayerHandoff.officialMusicUri(
      'dQw4w9WgXcQ&autoplay=1'), throwsArgumentError);
  });

  test('embed supported only where plugin implements the player', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      expect(
        YoutubePlayerHandoff.supportsEmbeddedPlayer(platform: platform),
        isTrue,
      );
    }
    for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
      expect(
        YoutubePlayerHandoff.supportsEmbeddedPlayer(platform: platform),
        isFalse,
      );
      expect(
        YoutubePlayerHandoff.supportsEmbeddedPlayer(
          platform: platform, isWeb: true),
        isTrue,
      );
    }
  });
}
