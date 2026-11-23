import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_controller.dart';

/// App-wide sleep timer. It is owned by the global player feature rather than
/// a Settings route, so navigating away does not cancel a scheduled pause.
class SleepTimerController extends Notifier<DateTime?> {
  Timer? _timer;

  @override
  DateTime? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void schedule(Duration duration) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive');
    }
    _timer?.cancel();
    final endsAt = DateTime.now().add(duration);
    state = endsAt;
    _timer = Timer(duration, () {
      _timer = null;
      state = null;
      unawaited(ref.read(playerControllerProvider.notifier).pause());
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerController, DateTime?>(SleepTimerController.new);
