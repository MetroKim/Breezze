import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/features/player/sleep_timer_controller.dart';

void main() {
  test('sleep timer can be scheduled and cancelled', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(sleepTimerProvider.notifier);
    controller.schedule(const Duration(minutes: 15));

    expect(container.read(sleepTimerProvider), isNotNull);
    expect(container.read(sleepTimerProvider)!.isAfter(DateTime.now()), isTrue);

    controller.cancel();
    expect(container.read(sleepTimerProvider), isNull);
  });

  test('rescheduling replaces the previous deadline', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(sleepTimerProvider.notifier);
    controller.schedule(const Duration(minutes: 60));
    final firstDeadline = container.read(sleepTimerProvider)!;

    controller.schedule(const Duration(minutes: 15));
    final secondDeadline = container.read(sleepTimerProvider)!;

    expect(secondDeadline.isBefore(firstDeadline), isTrue);
    controller.cancel();
  });
}
