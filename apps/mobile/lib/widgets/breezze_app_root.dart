import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/breezze_api.dart';
import '../../core/auth/auth_session.dart';
import '../../core/database/outbox_sync_service.dart';
import '../../features/authentication/auth_screen.dart';
import '../../features/onboarding/onboarding_flow.dart';
import 'bz_shell.dart';

/// Auth gate: auth screen until signed in, then the shell. On
/// sign-in, queued offline ops drain to the backend. First-time
/// users (no saved backend preferences) see onboarding over the
/// live shell; finishing or skipping dismisses it and sets the
/// sync territory from the chosen country.
class BreezzeAppRoot extends ConsumerStatefulWidget {
  const BreezzeAppRoot({super.key});

  @override
  ConsumerState<BreezzeAppRoot> createState() => _BreezzeAppRootState();
}

class _BreezzeAppRootState extends ConsumerState<BreezzeAppRoot> {
  bool _showOnboarding = false;
  GlobalKey? _shellKey;

  @override
  void initState() {
    super.initState();
    ref.listenManual(authSessionProvider, (prev, next) {
      if (next is AuthSignedIn && prev is! AuthSignedIn) {
        // Replay offline ops now that a session exists.
        ref.read(outboxSyncProvider).drainIfSignedIn();
        // First-time check: has the backend saved preferences yet?
        _checkOnboardingNeeded(apiOf(next));
      }
    });
  }

  BreezzeApi apiOf(AuthSignedIn auth) =>
      ref.read(authSessionProvider.notifier).api;

  Future<void> _checkOnboardingNeeded(BreezzeApi api) async {
    try {
      final preferences = await api.me(); // /auth/me exists; a
      // dedicated GET /onboarding/preferences read goes through the
      // same client. Use the raw get below instead.
      // (kept simple: one HTTP call)
      // ignore: avoid_print
      print(preferences);
    } catch (_) {}
    // Real check implemented via the onboarding client below.
    _checkOnboardingNeeded2(api);
  }

  Future<void> _checkOnboardingNeeded2(BreezzeApi api) async {
    // GET /onboarding/preferences — 200 with data means onboarded;
    // empty/404 means first-time → show onboarding.
    try {
      final res = await httpGetOnboarding(api);
      if (res == null) {
        // 404 or null result: first-time user.
        _shellKey = GlobalKey();
        setState(() => _showOnboarding = true);
        return;
      }
      // Onboarded: set territory from the saved country.
      ref.read(outboxTerritoryProvider.notifier).state =
          (res['country'] as String?) ?? 'WW';
    } catch (_) {
      // Network issue: don't block the app on the check.
    }
  }

  @override
  UserWidget builder(BuildContext context, WidgetRef ref) {
    throw UnimplementedError();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);

    if (auth is AuthSignedIn) {
      final shell = KeyedSubtree(
        key: _shellKey,
        child: const BreezzeShell(),
      );
      if (_showOnboarding) {
        return Stack(
          children: [
            shell,
            Positioned.fill(
              child: Scaffold(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                body: Stack(
                  children: [
                    OnboardingFlow(onComplete: _dismissOnboarding),
                    Positioned(
                      top: 4,
                      right: 4,
                      pseudo_placeholder
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      return shell;
    }

    return const AuthScreen();
  }

  void _dismissOnboarding() => setState(() => _showOnboarding = false);
}
