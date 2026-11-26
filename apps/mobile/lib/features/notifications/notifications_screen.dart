import 'package:material_ui/material_ui.dart';

import '../../app/followed_artist_store.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import '../../widgets/bz_branded_app_bar.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _marking = {};
  final Set<String> _following = {};
  final _follows = FollowedArtistStore();
  List<Map<String, dynamic>> _suggestedArtists = const [];
  int _generation = 0;
  String? _owner;

  bool _stillOwner(String owner, int generation) {
    if (!mounted || generation != _generation) return false;
    final auth = ref.read(authSessionProvider);
    return auth is AuthSignedIn && auth.userId == owner;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final auth = ref.read(authSessionProvider);
    final owner = auth is AuthSignedIn ? auth.userId : null;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
      _suggestedArtists = [];
      _owner = owner;
    });
    if (owner == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to see your activity.';
      });
      return;
    }

    try {
      final items = await ref.read(authSessionProvider.notifier).api.notifications();
      if (!_stillOwner(owner, generation)) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      // Suggestions never block notification delivery; only real artist
      // records from the provider are displayed, based on the user's
      // existing onboarding preferences.
      await _loadSuggestions(owner, generation);
    } catch (_) {
      if (!_stillOwner(owner, generation)) return;
      setState(() {
        _loading = false;
        _error = 'Notifications could not be loaded. Check your connection and retry.';
      });
    }
  }

  Future<void> _loadSuggestions(String owner, int generation) async {
    try {
      final api = ref.read(authSessionProvider.notifier).api;
      final preferences = await api.onboardingPreferences();
      if (!_stillOwner(owner, generation)) return;
      final artists = preferences['favoriteArtists'];
      final genres = preferences['genres'];
      String? query;
      if (artists is List && artists.isNotEmpty &&
          artists.first is String && (artists.first as String).trim().length >= 2) {
        query = (artists.first as String).trim();
      } else if (genres is List && genres.isNotEmpty &&
          genres.first is String && (genres.first as String).trim().length >= 2) {
        query = (genres.first as String).trim();
      }
      if (query == null) return;
      final results = await api.discoveryArtistSearch(query);
      final currentFollows = await _follows.load(owner);
      if (!_stillOwner(owner, generation)) return;
      final alreadyFollowed = currentFollows.map((artist) => artist.artistKey).toSet();
      final raw = results['items'];
      if (raw is! List) return;
      final suggestions = <Map<String, dynamic>>[];
      for (final row in raw) {
        if (row is! Map) continue;
        final id = row['id'];
        final name = row['name'];
        if (id is! String || !RegExp(r'^[0-9]+$').hasMatch(id) ||
            name is! String || name.trim().isEmpty) continue;
        if (alreadyFollowed.contains('catalog:dz_$id')) continue;
        final art = row['artworkUrl'];
        final uri = art is String ? Uri.tryParse(art) : null;
        suggestions.add({
          'id': id,
          'name': name,
          if (uri != null && uri.scheme == 'https') 'artworkUrl': art,
        });
        if (suggestions.length == 6) break;
      }
      setState(() => _suggestedArtists = suggestions);
    } catch (_) {
      // No synthetic artists or recommendations on provider/auth failure.
    }
  }

  Future<void> _followArtist(String id, String name) async {
    final owner = _owner;
    if (owner == null || !_stillOwner(owner, _generation) ||
        _following.contains(id)) return;
    setState(() => _following.add(id));
    try {
      // Persist immediately to the owner-scoped outbox. Cloud replay is
      // handled by the existing followed-artist sync service.
      await _follows.follow(owner, 'catalog:dz_$id', name);
      if (!_stillOwner(owner, _generation)) return;
      setState(() {
        _suggestedArtists.removeWhere((item) => item['id'] == id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Following $name in your Breezze Library')),
      );
    } catch (_) {
      if (mounted && _owner == owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not follow this artist. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _following.remove(id));
    }
  }

  Future<void> _markRead(String id) async {
    if (_marking.contains(id)) return;
    setState(() => _marking.add(id));
    try {
      await ref.read(authSessionProvider.notifier).api.markNotificationRead(id);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final item in _items)
            if (item['id'] == id)
              {...item, 'readAt': DateTime.now().toUtc().toIso8601String()}
            else
              item,
        ];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not mark notification as read.')),
        );
      }
    } finally {
      if (mounted) setState(() => _marking.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = _items.where((item) => item['readAt'] == null).length;
    final unreadItems = _items.where((item) => item['readAt'] == null).toList();
    final earlierItems = _items.where((item) => item['readAt'] != null).toList();
    Widget activityRow(Map<String, dynamic> item) {
      final id = item['id'] as String? ?? '';
      final isRead = item['readAt'] != null;
      return Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                BzSvgIcon(
                  name: 'bell',
                  color: isRead ? theme.bzText2 : theme.bzText1,
                ),
                if (!isRead)
                  const Positioned(
                    right: -3, top: -3,
                    child: CircleAvatar(radius: 4, backgroundColor: Colors.white),
                  ),
              ],
            ),
            title: Text(
              item['title'] as String? ?? 'Breezze update',
              style: TextStyle(
                fontWeight: isRead ? FontWeight.w400 : FontWeight.w700,
              ),
            ),
            subtitle: Text(item['body'] as String? ?? ''),
            isThreeLine: true,
            trailing: isRead
                ? null
                : TextButton(
                    onPressed: _marking.contains(id) || id.isEmpty
                        ? null
                        : () => _markRead(id),
                    child: Text(_marking.contains(id) ? 'Saving…' : 'Mark read'),
                  ),
          ),
          Divider(height: 1, color: theme.bzSeparator),
        ],
      );
    }

    return Scaffold(
      appBar: BzBrandedAppBar(
        title: unread == 0 ? 'Activity' : 'Activity ($unread)',
        leading: IconButton(
          tooltip: 'Back',
          icon: const BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh activity',
            onPressed: _load,
            icon: const BzSvgIcon(name: 'refresh'),
          ),
        ],
      ),
      body: _loading
          ? ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 5,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, __) => const BzSkeletonTrackRow(),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
                    children: [
                      if (_items.isEmpty)
                        const ListTile(
                          title: Text('You are all caught up'),
                          subtitle: Text('Updates from Breezze will appear here.'),
                        ),
                      if (unreadItems.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: Text('Unread', style: theme.textTheme.titleMedium),
                        ),
                        for (final item in unreadItems) activityRow(item),
                      ],
                      if (earlierItems.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: Text('Earlier', style: theme.textTheme.titleMedium),
                        ),
                        for (final item in earlierItems) activityRow(item),
                      ],
                      if (_suggestedArtists.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Divider(color: theme.bzSeparator),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('Suggested for you',
                              style: theme.textTheme.titleLarge),
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Real artists discovered from your listening interests',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.bzText2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final artist in _suggestedArtists)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.bzSurface2,
                              foregroundImage: artist['artworkUrl'] is String
                                  ? NetworkImage(artist['artworkUrl'] as String)
                                  : null,
                              child: const BzSvgIcon(name: 'user-round'),
                            ),
                            title: Text(artist['name'] as String),
                            subtitle: const Text('Deezer artist discovery'),
                            trailing: TextButton(
                              onPressed: _following.contains(artist['id'])
                                  ? null
                                  : () => _followArtist(
                                        artist['id'] as String,
                                        artist['name'] as String,
                                      ),
                              child: Text(_following.contains(artist['id'])
                                  ? 'Following…' : 'Follow'),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
