import 'package:breezze/app/download_job_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('download job files are partitioned by account with no raw user id', () {
    final alice = downloadJobOwnerDirectory('alice@example.test');
    final bob = downloadJobOwnerDirectory('bob@example.test');
    expect(alice, isNot(bob));
    expect(alice, startsWith('account-'));
    expect(alice, hasLength(72)); // "account-" + SHA256 hex digest.
    expect(alice, isNot(contains('alice')));
    expect(alice, downloadJobOwnerDirectory('alice@example.test'));
  });

  test('download job folder cannot be anonymous or a traversal path', () {
    expect(() => downloadJobOwnerDirectory(''), throwsArgumentError);
    expect(() => downloadJobOwnerDirectory('  '), throwsArgumentError);
    expect(downloadJobOwnerDirectory('../other-user'), isNot(contains('../')));
  });
}
