import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import '../../widgets/bz_branded_app_bar.dart';
import '../player/player_controller.dart';

/// Nonproduction, opt-in real-music acceptance screen. One explicitly
/// public-domain recording, never mislabeled as a YouTube Music track.
class AudioProofScreen extends ConsumerStatefulWidget {
  const AudioProofScreen({super.key});

  @override
  ConsumerState<AudioProofScreen> createState() => _AudioProofScreenState();
}

class _AudioProofScreenState extends ConsumerState<AudioProofScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _track;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _requestVersion++;
    super.dispose();
  }

  Future<void> _load() async {
    const enabled = bool.fromEnvironment(
      'BREEZZE_PUBLIC_AUDIO_PROOF',
      defaultValue: false,
    );
    if (!enabled) {
      setState(() {
        _loading = false;
        _error = 'Audio proof is disabled in this build.';
      });
      return;
    }
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) {
      setState(() {
        _loading = false;
        _error = 'Sign in to test the authorized audio source.';
      });
      return;
    }
    final owner = auth.userId;
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
      _track = null;
    });
    try {
      final track = await ref.read(authSessionProvider.notifier)
          .api.audioProofTrack();
      if (!mounted || version != _requestVersion) return;
      final current = ref.read(authSessionProvider);
      if (current is! AuthSignedIn || current.userId != owner) return;
      if (track['id'] != 'bz:public_domain:promise' ||
          track['source'] != 'wikimedia_commons' ||
          track['fullTrack'] != true) {
        throw StateError('Unexpected audio proof response');
      }
      setState(() {
        _loading = false;
        _track = track;
      });
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _error = 'The public-domain music proof is unavailable. Retry.';
      });
    }
  }

  Future<void> _play() async {
    if (_loading || _track == null) return;
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn) return;
    final owner = auth.userId;
    final track = _track!;
    final sound = TrackInfo(
      id: track['id'] as String,
      title: track['title'] as String,
      artist: track['artist'] as String,
      artworkUrl: null,
      duration: Duration(seconds: (track['durationSec'] as num).toInt()),
    );
    try {
      await ref.read(playerControllerProvider.notifier).playTrack(
        trackId: sound.id,
        queue: [sound],
        startIndex: 0,
        origin: 'audio_proof',
        sourceContext: 'Public-domain full-track acceptance',
      );
    } catch (_) {
      if (!mounted) return;
      final current = ref.read(authSessionProvider);
      if (current is! AuthSignedIn || current.userId != owner) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playback could not start. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authSessionProvider, (before, after) {
      final oldOwner = before is AuthSignedIn ? before.userId : null;
      final newOwner = after is AuthSignedIn ? after.userId : null;
      if (oldOwner == newOwner) return;
      _requestVersion++;
      setState(() {
        _track = null;
        _error = 'Account changed. Reload to verify the source.';
        _loading = false;
      });
    });
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: const BzBrandedAppBar(
        title: 'Full-song audio proof',
        subtitle: 'Public-domain recording',
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Container(
              height: 230,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.bzSurface1,
                borderRadius: BorderRadius.circular(18),
              ),
              child: BzBnoteMark(size: 76, color: theme.bzText1),
            ),
            const SizedBox(height: 22),
            Text(
              _track?['title'] as String? ?? 'Promise',
              style: theme.textTheme.headlineLarge,
            ),
            const SizedBox(height: 6),
            Text(
              _track?['artist'] as String? ?? 'Keith Adler',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.bzText2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'A real 2:28 ambient song released into the public domain '
              'by its author. Its MP3 was decoded successfully from '
              'Wikimedia Commons in GitHub Actions. Not YouTube Music.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null) ...[
              Text(_error!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ] else
              FilledButton.icon(
                onPressed: _play,
                icon: const BzSvgIcon(name: 'play'),
                label: const Text('Play full song in Breezze'),
              ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://commons.wikimedia.org/wiki/File:Promise.ogg'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('View source and public-domain license'),
            ),
            const SizedBox(height: 12),
            Text(
              'Experimental, sign-in required. No offline download or '
              'YouTube extraction is enabled by this test.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.bzText2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
