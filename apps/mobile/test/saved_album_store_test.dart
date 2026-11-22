import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/app/saved_album_store.dart';

void main() {
  test('album metadata survives local JSON round trip', () {
    final album = SavedAlbum(
      id: '123456',
      title: 'First Light',
      artist: 'Artist',
      artworkUrl: 'https://example.com/art.jpg',
      catalogUrl: 'https://example.com/album',
      addedAt: DateTime.utc(2026, 1, 2),
    );
    final restored = SavedAlbum.fromJson(album.toJson());
    expect(restored.id, '123456');
    expect(restored.title, 'First Light');
    expect(restored.artist, 'Artist');
    expect(restored.artworkUrl, album.artworkUrl);
    expect(restored.catalogUrl, album.catalogUrl);
    expect(restored.addedAt, album.addedAt);
  });

  test('album metadata has safe missing-field defaults', () {
    final album = SavedAlbum.fromJson({'id': '789'});
    expect(album.title, 'Unknown album');
    expect(album.artist, 'Unknown artist');
    expect(album.artworkUrl, isNull);
  });
}
