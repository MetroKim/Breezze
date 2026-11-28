import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/core/audio/commons_device_download.dart';

void main() {
  Map<String, dynamic> valid() => {
    'provider': 'wikimedia_commons',
    'title': 'Example song',
    'fileTitle': 'File:Example song.mp3',
    'kind': 'audio',
    'mimeType': 'audio/mpeg',
    'bytes': 4500,
    'sourcePage': 'https://commons.wikimedia.org/wiki/File%3AExample_song.mp3',
    'license': 'CC BY 4.0',
    'licenseUrl': 'https://creativecommons.org/licenses/by/4.0/',
    'creator': 'Independent creator',
    'streamUrl': 'https://upload.wikimedia.org/wikipedia/commons/a/ab/Example_song.mp3',
    'downloadUrl': 'https://upload.wikimedia.org/wikipedia/commons/a/ab/Example_song.mp3',
    'downloadAllowed': true,
  };

  test('allows a properly attributed on-demand MP3 saved on device', () {
    final file = CommonsDeviceMedia.fromJson(valid());
    expect(file.extension, 'mp3');
    expect(file.downloadAllowed, isTrue);
    expect(file.toLocalMetadata()['sourcePage'],
      'https://commons.wikimedia.org/wiki/File%3AExample_song.mp3');
  });

  test('accepts video/webm CC0 for native video where decoder is available', () {
    final item = valid()
      ..['kind'] = 'video'
      ..['mimeType'] = 'video/webm'
      ..['fileTitle'] = 'File:Public film.webm'
      ..['streamUrl'] =
        'https://upload.wikimedia.org/wikipedia/commons/a/ab/Public_film.webm'
      ..['downloadUrl'] =
        'https://upload.wikimedia.org/wikipedia/commons/a/ab/Public_film.webm'
      ..['license'] = 'CC0 1.0'
      ..['licenseUrl'] = 'https://creativecommons.org/publicdomain/zero/1.0/';
    expect(CommonsDeviceMedia.fromJson(item).extension, 'webm');
  });

  test('recognizes actual Commons application/ogg AUDIO and VIDEO manifests', () {
    final audio = valid()
      ..['fileTitle'] = 'File:Commons concert.oga'
      ..['title'] = 'Commons concert'
      ..['mimeType'] = 'application/ogg'
      ..['streamUrl'] =
          'https://upload.wikimedia.org/wikipedia/commons/a/ab/Commons_concert.oga'
      ..['downloadUrl'] =
          'https://upload.wikimedia.org/wikipedia/commons/a/ab/Commons_concert.oga'
      ..['durationSec'] = 292.596;
    final recording = CommonsDeviceMedia.fromJson(audio);
    expect(recording.extension, 'ogg');
    expect(recording.durationSec, 292.596);
    expect(recording.toLocalMetadata()['durationSec'], 292.596);

    final video = Map<String, dynamic>.from(audio)
      ..['kind'] = 'video'
      ..['fileTitle'] = 'File:Commons film.ogv'
      ..['streamUrl'] =
          'https://upload.wikimedia.org/wikipedia/commons/a/ab/Commons_film.ogv'
      ..['downloadUrl'] =
          'https://upload.wikimedia.org/wikipedia/commons/a/ab/Commons_film.ogv';
    expect(CommonsDeviceMedia.fromJson(video).extension, 'ogv');
  });

  test('refuses unrelated hosts, restricted licenses and absent permissions', () {
    for (final bad in [
      {'streamUrl': 'https://stream-ripper.example.com/file.mp3'},
      {'downloadUrl': 'http://upload.wikimedia.org/file.mp3'},
      {'licenseUrl': 'https://creativecommons.org/licenses/by-nc/4.0/'},
      {'downloadAllowed': false},
      {'sourcePage': 'https://example.org/fake'},
      {'bytes': 0},
      {'kind': 'image'},
      {'mimeType': 'application/octet-stream'},
    ]) {
      expect(
        () => CommonsDeviceMedia.fromJson({...valid(), ...bad}),
        throwsFormatException,
      );
    }
  });
}
