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
    expect(restored.genres, isEmpty);
    expect(restored.isCompilation, isFalse);
  });

  test('album metadata has safe missing-field defaults', () {
    final album = SavedAlbum.fromJson({'id': '789'});
    expect(album.title, 'Unknown album');
    expect(album.artist, 'Unknown artist');
    expect(album.artworkUrl, isNull);
  });
  test('verified genre/compilation metadata round-trips without inference', () {
    final compilation = SavedAlbum(
      id: '123',
      title: 'Music Selection',
      artist: 'Various Artists',
      genres: const ['Electronic', 'Dance'],
      isCompilation: true,
      addedAt: DateTime.utc(2026),
    );
    final restored = SavedAlbum.fromJson(compilation.toJson());
    expect(restored.genres, ['Electronic', 'Dance']);
    expect(restored.isCompilation, isTrue);
    expect(
      SavedAlbumGroups.compilations([restored]).map((album) => album.id),
      ['123'],
    );
    // Artist/title alone must not imply compilation status.
    final unknown = SavedAlbum(
      id: '124',
      title: 'Greatest Hits',
      artist: 'Various Artists',
      addedAt: DateTime.utc(2026),
    );
    expect(SavedAlbumGroups.compilations([unknown]), isEmpty);
  });

  test('genre groups come from album metadata, de-duplicate case', () {
    final a = SavedAlbum(
      id: 'a',
      title: 'One',
      artist: 'Artist A',
      genres: const ['Afrobeats', 'Dance'],
      addedAt: DateTime.utc(2026),
    );
    final b = SavedAlbum(
      id: 'b',
      title: 'Two',
      artist: 'Artist B',
      genres: const ['afrobeats'],
      addedAt: DateTime.utc(2026),
    );
    final uncategorized = SavedAlbum(
      id: 'c',
      title: 'Three',
      artist: 'Artist C',
      addedAt: DateTime.utc(2026),
    );
    expect(SavedAlbumGroups.genres([a, b, uncategorized]),
        ['Afrobeats', 'Dance']);
    expect(SavedAlbumGroups.forGenre([a, b, uncategorized], 'AFROBEATS')
        .map((album) => album.id).toList(), ['a', 'b']);
  });

  test('legacy saved albums still decode without new metadata', () {
    final album = SavedAlbum.fromJson({
      'id': 'old-id',
      'title': 'Old Album',
      'artist': 'Artist',
      'genres': null,
      'isCompilation': null,
    });
    expect(album.genres, isEmpty);
    expect(album.isCompilation, isFalse);
  });

}
