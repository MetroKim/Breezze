import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';

void main() {
  test('authorized OpenSubsonic IDs can ask backend for a full-song session', () {
    expect(isOpenSubsonicTrackId('bz:opensubsonic:original-song'), isTrue);
    expect(isMetadataOnlyTrackId('bz:opensubsonic:original-song'), isFalse);
    expect(canQueueTrackId('bz:opensubsonic:original-song'), isTrue);
    expect(canOfferPlaybackAction('bz:opensubsonic:original-song'), isTrue);
    expect(canRequestOfflineDownload('bz:opensubsonic:original-song'), isFalse);
  });

  test('malformed aliases and metadata provider IDs remain non-playable', () {
    for (final id in const [
      'bz:opensubsonic:',
      'bz:opensubsonic:../secret',
      'bz:opensubsonic:my song',
      'bz:spotify:1234567890123456789012',
      'bz:deezer:1234',
      'bz:youtube_music:aqz-KE-bpKQ',
    ]) {
      expect(canQueueTrackId(id), isFalse, reason: id);
    }
  });
}
