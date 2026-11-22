import 'package:flutter_test/flutter_test.dart';
import 'package:breezze/app/library_section_preferences_store.dart';

void main() {
  test('valid library section settings survive normalization', () {
    expect(
      LibrarySectionPreferencesStore.normalize([
        'Playlists', 'Albums', 'Genres', 'Albums', 'Fake'
      ]),
      equals({'Playlists', 'Albums', 'Genres'}),
    );
  });

  test('an empty or obsolete selection restores a usable library', () {
    expect(
      LibrarySectionPreferencesStore.normalize(['Obsolete']),
      equals(LibrarySectionPreferencesStore.defaultSections),
    );
  });
}
