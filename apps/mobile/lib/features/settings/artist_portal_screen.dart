import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';

class ArtistPortalScreen extends ConsumerStatefulWidget {
  const ArtistPortalScreen({super.key});

  @override
  ConsumerState<ArtistPortalScreen> createState() => _ArtistPortalScreenState();
}

class _ArtistPortalScreenState extends ConsumerState<ArtistPortalScreen> {
  final _artistId = TextEditingController();
  Map<String, dynamic> _dashboard = const {};
  Map<String, dynamic> _analytics = const {};
  List<Map<String, dynamic>> _claims = const [];
  bool _loading = true;
  bool _claiming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _artistId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(authSessionProvider.notifier).api;
      final results = await Future.wait([
        api.artistDashboard(),
        api.artistAnalytics(),
        api.artistClaims(),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as Map<String, dynamic>;
        _analytics = results[1] as Map<String, dynamic>;
        _claims = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Artist information could not be loaded. Try again.';
      });
    }
  }

  Future<void> _claim() async {
    final id = _artistId.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _claiming = true;
      _error = null;
    });
    try {
      await ref.read(authSessionProvider.notifier).api.claimArtist(id);
      _artistId.clear();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Claim could not be submitted. Check the artist ID and whether it is already claimed.');
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = _analytics['totals'] is Map
        ? _analytics['totals'] as Map
        : const {};
    final topTracks = _analytics['topTracks'] is List
        ? (_analytics['topTracks'] as List).whereType<Map>().toList()
        : const <Map>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Artist Portal'),
        leading: IconButton(
          icon: BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [IconButton(onPressed: _load, icon: const BzSvgIcon(name: 'refresh'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                Row(
                  children: [
                    Expanded(child: _Metric(label: 'Artist claims', value: '${_dashboard['activeClaims'] ?? 0}')),
                    const SizedBox(width: 12),
                    Expanded(child: _Metric(label: 'Total plays', value: '${totals['plays'] ?? 0}')),
                  ],
                ),
                const SizedBox(height: 24),
                Text('YOUR CLAIMS', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                if (_claims.isEmpty)
                  const ListTile(title: Text('No artist claims yet'))
                else
                  for (final claim in _claims)
                    ListTile(
                      leading: const BzSvgIcon(name: 'mic'),
                      title: Text('Artist ${claim['artistId'] ?? ''}'),
                      subtitle: Text('Status: ${claim['status'] ?? 'pending'}'),
                    ),
                const SizedBox(height: 20),
                Text('CLAIM AN ARTIST', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                const Text('Enter the artist ID supplied by Breezze support or your artist profile. Claims are reviewed before dashboard access is granted.'),
                const SizedBox(height: 8),
                TextField(
                  controller: _artistId,
                  decoration: const InputDecoration(labelText: 'Artist ID (UUID)'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _claiming ? null : _claim,
                  child: Text(_claiming ? 'Submitting…' : 'Submit claim'),
                ),
                const SizedBox(height: 24),
                Text('TOP TRACKS', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                if (topTracks.isEmpty)
                  const ListTile(title: Text('Approved artist analytics will appear here.'))
                else
                  for (final track in topTracks)
                    ListTile(
                      leading: const BzSvgIcon(name: 'music-note'),
                      title: Text(track['title'] as String? ?? 'Track'),
                      trailing: Text('${track['plays'] ?? 0} plays'),
                    ),
              ],
            ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
