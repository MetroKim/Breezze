import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../core/database/outbox_sync_service.dart';
import '../../features/authentication/auth_screen.dart';
import '../../features/onboarding/onboarding_flow.dart';
import 'bz_shell.dart';

/// Auth gate: auth screen until signed in, then the shell. On
/// sign-in, queued offline ops drain to the backend. First-time
/// users go through onboarding; the result sets the sync territory.
class BreezzeAppRoot extends ConsumerStatefulWidget {
  const BreezzeAppRoot({super.key});

  @override
  ConsumerState<BreezzeAppRoot> createState() => _BreezzeAppRootState();
}

class _BreezzeAppRootState extends ConsumerState<BreezzeAppRoot> {
  bool _onboarded = false;
  GlobalKey? _shellKey;

  @override
  void initState() {
    super.initState();
    ref.listenManual(authSessionProvider, (prev, next) {
      if (next is AuthSignedIn && prev is! AuthSignedIn) {
        // Replay offline ops now that a session exists.
        ref.read(outboxSyncProvider).drainIfSignedIn();
        // First sign-in: run onboarding over the live shell.
        _shellKey = GlobalKey();
        setState(() => _onboarded = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);

    if (auth is AuthSignedIn) {
      final shell = KeyedSubtree(
        key: _shellKey,
        child: const BreezzeShell(),
      );
      if (!_onboarded) {
        return Stack(
          children: [
            shell,
            Positioned.fill(child: _OnboardingOverlay(onDone: _finishOnboarding)),
          ],
        );
      }
      return shell;
    }

    return const AuthScreen();
  }

  void _finishOnboarding() => setState(() => _onboarded = true);
}

/// Full-screen onboarding over the shell — dismissed on completion.
class _OnboardingOverlay extends StatelessWidget {
  final VoidCallback onDone;

  const _OnboardingOverlay({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Dismissable flow; pops itself via Navigator.of(context).
          const OnboardingFlow(),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: TextButton(onPressed: onDone, child: const Text('Skip')),
            ),
          ),
        ],
      ),
    );
  }
}
