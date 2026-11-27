import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/playback_source_policy.dart';

void main() {
  test('only the exact verified public-domain proof track can enter queue', () {
    expect(isPublicAudioProofTrackId('bz:public_domain:promise'), isTrue);
    expect(canQueueTrackId('bz:public_domain:promise'), isTrue);
    expect(canOfferPlaybackAction('bz:public_domain:promise'), isTrue);
    expect(isMetadataOnlyTrackId('bz:public_domain:promise'), isFalse);
    expect(canRequestOfflineDownload('bz:public_domain:promise'), isFalse);

    expect(isPublicAudioProofTrackId('bz:public_domain:other'), isFalse);
    expect(canQueueTrackId('bz:public_domain:other'), isFalse);
    expect(canQueueTrackId('bz:youtube_music:aqz-KE-bpKQ'), isFalse);
    expect(canQueueTrackId('bz:spotify:1234567890123456789012'), isFalse);
    expect(canQueueTrackId('bz:deezer:12345'), isFalse);
  });
}
