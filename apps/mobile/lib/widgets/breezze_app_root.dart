import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../core/database/outbox_sync_service.dart';
import '../../features/authentication/auth_screen.dart';
import 'bz_shell.dart';

/// Auth gate: shows the auth screen until signed in, then the main
/// shell. On sign-in, queued offline ops (favorites / plays) drain to
/// the backend. Navigation never resets playback (§26.3).
class BreezzeAppRoot extends ConsumerStatefulWidget {
  const BreezzeAppRoot({super.key});

  @override
  ConsumerState<BreezzeAppRoot> createState() => _BreezzeAppRootState();
}

class _BreezzeAppRootState extends ConsumerState<BreezzeAppRoot> {
  @override
  void initState() {
    super.initState();
    // When a session appears, replay offline ops to the backend.
    ref.listenManual(authSessionProvider, (prev, next) {
      if (next is AuthSignedIn && prev is! AuthSignedIn) {
        ref.read(outboxSyncProvider).drainIfSignedIn();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);

    if (auth is AuthSignedIn) {
      return const BreezzeShell();
    }

    return const AuthScreen();
  }
}
