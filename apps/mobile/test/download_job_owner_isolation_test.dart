import 'package:breezze/app/downloads_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download-job filenames are distinct and stable across listeners', () {
    final alice = scopedDownloadJobsFilename('alice-123');
    final bob = scopedDownloadJobsFilename('bob-456');
    expect(alice, isNot(bob));
    expect(alice, scopedDownloadJobsFilename('alice-123'));
    expect(alice, isNot('jobs.json'));
    expect(bob, isNot('jobs.json'));
  });

  test('untrusted owner IDs cannot traverse download job directories', () {
    for (final user in ['../alice', 'bob/../alice', 'a:b', 'someone@example.org']) {
      final filename = scopedDownloadJobsFilename(user);
      expect(filename, isNot(contains('/')));
      expect(filename, isNot(contains('..')));
      expect(filename, isNot(contains('\\')));
      expect(filename, endsWith('.json'));
    }
  });

  test('signed-out or blank ownership cannot create a queue filename', () {
    expect(() => scopedDownloadJobsFilename(''), throwsArgumentError);
    expect(() => scopedDownloadJobsFilename('   '), throwsArgumentError);
  });
}
