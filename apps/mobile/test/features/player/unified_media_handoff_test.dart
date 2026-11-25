import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/features/player/unified_media_handoff.dart';

void main() {
  test('unified media route preserves track order and rejects metadata-only videos', () {
    final tracks = [
      const TrackInfo(id: 'bz:youtube_music:dQw4w9WgXcQ', title: 'A'),
      const TrackInfo(id: 'bzv:dQw4w9WgXcQ', title: 'Video'),
      const TrackInfo(id: 'bz:youtube_music:aqz-KE-bpKQ', title: 'B'),
      const TrackInfo(id: 'bz:youtube_music:dQw4w9WgXcQ', title: 'Duplicate'),
      const TrackInfo(id: 'bz:deezer_preview:123', title: 'Preview'),
    ];
    final filtered = youtubeMusicQueue(tracks);
    expect(filtered.map((track) => track.title).toList(), ['A', 'B']);
    expect(filtered.map((track) => track.id).toList(), [
      'bz:youtube_music:dQw4w9WgXcQ',
      'bz:youtube_music:aqz-KE-bpKQ',
    ]);
  });
}
