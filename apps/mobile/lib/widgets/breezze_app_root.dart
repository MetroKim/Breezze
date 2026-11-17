import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../features/authentication/auth_screen.dart';
import 'bz_shell.dart';

/// Auth gate: shows the auth screen until signed in, then the main
/// shell. Navigation never resets playback (§26.3) — the shell and its
/// PlayerController survive across the auth boundary unchanged.
class BreezzeAppRoot extends ConsumerWidget {
  const BreezzeAppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);

    if (auth is AuthSignedIn || auth is AuthSigningIn) {
      // Keep the shell mounted during signing-in transitions so a
      // re-login doesn't rebuild the player tree.
      return auth is AuthSigningIn
          ? const AuthScreen()
          : const BreezzeShell();
    }

    return const AuthScreen();
  }
}
