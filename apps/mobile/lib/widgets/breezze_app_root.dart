import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import '../core/api/breezze_api.dart';
import '../features/onboarding/onboarding_controller.dart';

import '../core/auth/auth_session.dart';
import '../core/audio/just_audio_engine_adapter.dart';
import '../core/audio/encrypted_offline_audio_source.dart';
import '../core/audio/audio_service_bridge.dart';
import '../core/audio/background_audio.dart';
import '../core/audio/playback_queue_store.dart';
import '../core/database/migrate_to_drift.dart';
import '../core/database/outbox_sync_service.dart';
import '../features/player/player_controller.dart';
import '../features/authentication/auth_screen.dart';
import '../features/onboarding/onboarding_flow.dart';
import 'bz_shell.dart';
import 'bz_brand_icons.dart';

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

class _BreezzeAppRootState extends ConsumerState<BreezzeAppRoot> with WidgetsBindingObserver {
  bool _showOnboarding = false;
  int _accountVersion = 0;
  GlobalKey? _shellKey;
  ProviderContainer? _container;
  JustAudioEngineAdapter? _audioEngine;
  BackgroundAudioBridge? _backgroundBridge;
  final _queueStore = PlaybackQueueStore();
  String? _queueOwner;
  Future<void> _pendingQueueWrite = Future<void>.value();
  Future<void> _queueAuthTransition = Future<void>.value();
  ProviderSubscription<PlayerState>? _queueSubscription;

  void _saveQueueFor(String ownerId) {
    final snapshot = _container?.read(playerControllerProvider.notifier)
        .exportQueueSnapshot();
    // Preserve write order: a late position tick must never resurrect a queue
    // that was explicitly stopped a moment later.
    _pendingQueueWrite = _pendingQueueWrite.then((_) async {
      try {
        if (snapshot == null) {
          await _queueStore.clear(ownerId);
        } else {
          await _queueStore.save(ownerId, snapshot);
        }
      } catch (_) {
        // Secure storage failure must never interrupt playback.
      }
    });
  }

  Future<void> _restoreQueueFor(String ownerId, int version) async {
    try {
      final snapshot = await _queueStore.load(ownerId);
      if (!mounted || version != _accountVersion) return;
      final auth = ref.read(authSessionProvider);
      if (auth is! AuthSignedIn || auth.userId != ownerId) return;
      if (snapshot != null) {
        _container?.read(playerControllerProvider.notifier)
            .restoreQueueSnapshot(snapshot);
      }
    } catch (_) {
      // A missing, corrupt or platform-unsupported secure store is nonfatal.
    } finally {
      if (mounted && version == _accountVersion) {
        final auth = ref.read(authSessionProvider);
        if (auth is AuthSignedIn && auth.userId == ownerId) {
          _queueOwner = ownerId;
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _container = ProviderScope.containerOf(context, listen: false);
    _audioEngine = JustAudioEngineAdapter(
      encryptedSourceFactory: (path) async {
        // A stored path is never authority to decrypt another listener's
        // media. Check the currently signed-in account on every prepare.
        final auth = _container!.read(authSessionProvider);
        if (auth is! AuthSignedIn) {
          throw StateError('OFFLINE_SIGN_IN_REQUIRED');
        }
        return BreezzeEncryptedOfflineAudioSource.open(
          path: path,
          signedInUserId: auth.userId,
        );
      },
    );
    _container!.read(playerControllerProvider.notifier).attachEngine(_audioEngine!);
    _queueSubscription = ref.listenManual<PlayerState>(
      playerControllerProvider,
      (previous, next) {
        final owner = _queueOwner;
        final auth = ref.read(authSessionProvider);
        if (owner == null || auth is! AuthSignedIn || auth.userId != owner) {
          return;
        }
        final queueChanged = previous?.queueVersion != next.queueVersion ||
            previous?.currentTrack?.id != next.currentTrack?.id ||
            previous?.playbackState != next.playbackState;
        final positionCheckpoint =
            (previous?.position.inSeconds ?? 0) ~/ 20 !=
            next.position.inSeconds ~/ 20;
        if (queueChanged || positionCheckpoint) _saveQueueFor(owner);
      },
    );
    unawaited(_startBackgroundAudio());
    unawaited(migrateJsonStoresToDrift(_container!));
    unawaited(_container!.read(authSessionProvider.notifier).restoreSession());
    ref.listenManual(authSessionProvider, (prev, next) {
      final before = prev is AuthSignedIn ? prev.userId : null;
      final after = next is AuthSignedIn ? next.userId : null;
      if (before != after) {
        final version = ++_accountVersion;
        _showOnboarding = false;
        _shellKey = GlobalKey();
        ref.invalidate(onboardingProvider);
        ref.read(outboxTerritoryProvider.notifier).state = 'WW';

        // Snapshot the departing account before Stop clears the controller.
        // All data is written to account-scoped encrypted storage and never
        // contains a playback grant or a provider URL.
        if (before != null) _saveQueueFor(before);
        _queueOwner = null;
        _queueAuthTransition = _queueAuthTransition.then((_) async {
          if (before != null) {
            await _container?.read(playerControllerProvider.notifier).stop();
          }
          if (after != null) await _restoreQueueFor(after, version);
        }).catchError((Object _) {});
      }
      if (next is AuthSignedIn && before != after) {
        // Replay offline ops now that a session exists.
        unawaited(ref.read(outboxSyncProvider).drainIfSignedIn());

        // First-time check: has the backend saved preferences yet?
        _checkOnboardingNeeded(_accountVersion);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(authSessionProvider) is AuthSignedIn) {
      unawaited(ref.read(outboxSyncProvider).drainIfSignedIn());
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      final owner = _queueOwner;
      if (owner != null) _saveQueueFor(owner);
    }
  }

  Future<void> _startBackgroundAudio() async {
    try {
      final bridge = await startBackgroundAudio(_container!);
      if (!mounted) {
        await bridge.stop();
        return;
      }
      _backgroundBridge = bridge;
      final nativeSupported = supportsBreezzeSystemMediaSession(
        defaultTargetPlatform,
        isWeb: kIsWeb,
      );
      _container!
          .read(backgroundSessionAvailabilityProvider.notifier)
          .state = bridge is NoopBackgroundBridge
              ? (nativeSupported
                  ? BackgroundSessionAvailability.unavailable
                  : BackgroundSessionAvailability.unsupported)
              : BackgroundSessionAvailability.active;
      _container!.read(backgroundBridgeProvider.notifier).state = bridge;
      // Start one state-to-media-session subscription per app lifetime.
      _container!.read(backgroundSyncProvider);
    } catch (error) {
      if (mounted) {
        _container!
            .read(backgroundSessionAvailabilityProvider.notifier)
            .state = BackgroundSessionAvailability.unavailable;
      }
      // Report only the exception type; OAuth and OS plugin errors may
      // contain user paths or account details unsuitable for public CI logs.
      debugPrint('Breezze OS media session unavailable: ${error.runtimeType}');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final owner = _queueOwner;
    if (owner != null) _saveQueueFor(owner);
    _queueOwner = null;
    _queueSubscription?.close();
    unawaited(_backgroundBridge?.stop() ?? Future<void>.value());
    _container?.read(playerControllerProvider.notifier).detachEngine();
    _audioEngine?.dispose();
    super.dispose();
  }

  Future<void> _checkOnboardingNeeded(int version) async {
    final api = ref.read(authSessionProvider.notifier).api;
    try {
      final preferences = await api.onboardingPreferences();
      if (!mounted || version != _accountVersion) return;
      ref.read(outboxTerritoryProvider.notifier).state =
          preferences['country'] as String? ?? 'WW';
    } on BreezzeApiException catch (error) {
      if (mounted && version == _accountVersion && error.code == 'HTTP_404') {
        setState(() => _showOnboarding = true);
      }
    } catch (_) {
      // A listener can still open the cached library while offline.
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
      themeMode: ThemeMode.dark,
      theme: bzLightTheme(),
      darkTheme: bzDarkTheme(),
      home: Builder(
        builder: (context) {
          if (auth is AuthUninitialized) {
            return const Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BzBnoteMark(size: 92, color: Colors.white),
                    SizedBox(height: 22),
                    Text(
                      'Breezze',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    SizedBox(height: 32),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  ],
                ),
              ),
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
