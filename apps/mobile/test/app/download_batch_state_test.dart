import 'package:breezze/app/downloads_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late DownloadBatchController controller;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    controller = container.read(downloadBatchProvider.notifier);
  });

  DownloadBatchState batch() => container.read(downloadBatchProvider);

  test(
    'batch settles only after every tracked download reaches a terminal state',
    () {
      controller.begin('one');
      controller.begin('two');
      controller.setProgress('one', 1);
      controller.setProgress('two', 0.5);
      controller.setStatus('one', 'downloaded');

      expect(batch().isSettled, isFalse);
      expect(batch().fraction, 0.75);

      controller.setStatus('two', 'failed');

      expect(batch().isSettled, isTrue);
      expect(batch().completedCount, 1);
      expect(batch().failedCount, 1);
    },
  );

  test('settled outcome remains visible until dismissed', () {
    controller.begin('one');
    controller.setStatus('one', 'downloaded');

    expect(batch().isEmpty, isFalse);
    controller.dismiss();
    expect(batch().isEmpty, isTrue);
  });

  test('starting after settlement creates a fresh batch', () {
    controller.begin('old');
    controller.setStatus('old', 'downloaded');
    controller.begin('new');

    expect(batch().statuses.keys, ['new']);
    expect(batch().isSettled, isFalse);
  });
}
