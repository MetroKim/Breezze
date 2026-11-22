import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:audio_service/audio_service.dart' as audio;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:http/http.dart' as http;

import '../../core/auth/auth_session.dart';
import '../../core/audio/just_audio_engine_adapter.dart';
import '../../core/audio/breezze_audio_handler.dart';
import '../../core/database/migrate_to_drift.dart';
import '../../core/database/outbox_sync_service.dart';
import '../../features/player/player_controller.dart';
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
  ProviderContainer? _container;
  JustAudioEngineAdapter? _audioEngine;
  BreezzeAudioHandler? _audioHandler;
  ProviderSubscription<PlayerState>? _playerStateSubscription;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
    _audioEngine = JustAudioEngineAdapter();
    final playerController = _container!.read(playerControllerProvider.notifier);
    playerController.attachEngine(_audioEngine!);
    unawaited(_initializeMediaSession(playerController));
    unawaited(migrateJsonStoresToDrift(_container!));
    unawaited(_container!.read(authSessionProvider.notifier).restoreSession());
    ref.listenManual(authSessionProvider, (prev, next) {
      if (prev is AuthSignedIn && next is AuthSignedOut) {
        unawaited(ref.read(playerControllerProvider.notifier).stop());
      }
      if (next is AuthSignedIn && prev is! AuthSignedIn) {
        // Replay offline ops now that a session exists.
        ref.read(outboxSyncProvider).drainIfSignedIn();

        // First-time check: has the backend saved preferences yet?
        _checkOnboardingNeeded();
      }
    });
  }

  Future<void> _initializeMediaSession(PlayerController controller) async {
    // audio_service provides the native Android/iOS media session. Other
    // targets continue using Breezze's shared in-app player without trying to
    // start an unsupported platform service.
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      final initialized = await audio.AudioService.init(
        builder: () => BreezzeAudioHandler(controller),
        config: const audio.AudioServiceConfig(
          androidNotificationChannelId: 'com.breezze.audio',
          androidNotificationChannelName: 'Breezze playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: false,
        ),
      );
      if (!mounted) {
        await initialized.stop();
        return;
      }
      final handler = initialized as BreezzeAudioHandler;
      _audioHandler = handler;
      handler.updateFromPlayerState(
        _container!.read(playerControllerProvider),
        controller,
      );
      _playerStateSubscription = ref.listenManual<PlayerState>(
        playerControllerProvider,
        (previous, next) => handler.updateFromPlayerState(next, controller),
      );
    } catch (error, stackTrace) {
      debugPrint('Breezze native media session unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.close();
    _container?.read(playerControllerProvider.notifier).detachEngine();
    final engine = _audioEngine;
    if (engine != null) unawaited(engine.dispose());
    super.dispose();
  }

  Future<void> _checkOnboardingNeeded() async {
    final api = ref.read(authSessionProvider.notifier).api;
    try {
      final res = await http.get(
        Uri.parse('${api.baseUrl}/api/v1/onboarding/preferences'),
        headers: {
          if (api.accessToken != null)
            'Authorization': 'Bearer ${api.accessToken}',
        },
      );
      if (!mounted) return;

      if (res.statusCode == 404 || res.statusCode == 204) {
        // No saved preferences: first-time user.
        _shellKey = GlobalKey();
        setState(() => _showOnboarding = true);
        return;
      }
      if (res.statusCode >= 400) return;

      // Onboarded: set territory from the saved country.
      final body = jsonDecode(res.body);
      final data =
          body is Map && body['data'] is Map ? body['data'] : body;
      final country =
          data is Map ? data['country'] as String? : null;
      ref.read(outboxTerritoryProvider.notifier).state =
          country ?? 'WW';
    } catch (_) {
      // Network issue: don't block the app on the check.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);

    // Keep one MaterialApp/Navigator above every auth state. Previously the
    // signed-out gate rendered AuthScreen before the shell's nested
    // MaterialApp existed, leaving login/register without app navigation,
    // theme and inherited Material widgets.
    return MaterialApp(
      title: 'Breezze',
      debugShowCheckedModeBanner: false,
      theme: bzLightTheme(),
      darkTheme: bzDarkTheme(),
      home: Builder(
        builder: (context) {
          if (auth is AuthUninitialized) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

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
                      backgroundColor:
                          Theme.of(context).scaffoldBackgroundColor,
                      body: Stack(
                        children: [
                          OnboardingFlow(onComplete: _dismissOnboarding),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: SafeArea(
                              child: TextButton(
                                onPressed: _dismissOnboarding,
                                child: const Text('Skip'),
                              ),
                            ),
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
        },
      ),
    );
  }

  void _dismissOnboarding() => setState(() => _showOnboarding = false);
}
