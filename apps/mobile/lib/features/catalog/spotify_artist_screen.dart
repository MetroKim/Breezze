import 'dart:async';

import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/bootstrap.dart';
import '../../app/followed_artist_store.dart';
import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';

/// Spotify is the only provider of artist, album, release and track metadata
/// on this page. Tours explicitly report unavailable, rather than pretending
/// another provider's events came from Spotify.
class SpotifyArtistScreen extends ConsumerStatefulWidget {
  final String artistName;
  final String? artistId;
  final String? portraitUrl;
  final List<FavoriteTrack> savedTracks;
  final ValueChanged<Map<String, dynamic>> onTrackSelected;
  final ValueChanged<FavoriteTrack> onSavedTrackSelected;
  final ValueChanged<String> onSuggestedSearch;

  const SpotifyArtistScreen({
    super.key,
    required this.artistName,
    required this.artistId,
    required this.portraitUrl,
    required this.savedTracks,
    required this.onTrackSelected,
    required this.onSavedTrackSelected,
    required this.onSuggestedSearch,
  });

  @override
  ConsumerState<SpotifyArtistScreen> createState() => _SpotifyArtistScreenState();
}

class _SpotifyArtistScreenState extends ConsumerState<SpotifyArtistScreen> {
  final _follows = FollowedArtistStore();
  Map<String, dynamic>? _data;
  String? _artistId;
  String? _error;
  bool _loading = true;
  bool _savingFollow = false;
  FollowedArtist? _following;
  int _generation = 0;
  String? _initialOwner;

  String? _owner() {
    final auth = ref.read(authSessionProvider);
    return auth is AuthSignedIn ? auth.userId : null;
  }

  @override
  void initState() {
    super.initState();
    _initialOwner = _owner();
    _artistId = widget.artistId;
    unawaited(_loadArtist());
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _loadArtist() async {
    final generation = ++_generation;
    final owner = _initialOwner;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (owner == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to view this Spotify artist profile.';
      });
      return;
    }
    try {
      final api = ref.read(authSessionProvider.notifier).api;
      var id = widget.artistId;
      if (id == null) {
        // Library entries created before Spotify-only artist identities
        // need an exact name match; never navigate to a similarly named band.
        final discovery = await api.searchSpotifyArtists(widget.artistName);
        final items = discovery['value'];
        if (discovery['kind'] == 'ok' && items is List) {
          final match = items.whereType<Map>().where((row) =>
              row['name'] is String &&
              (row['name'] as String).trim().toLowerCase() ==
                  widget.artistName.trim().toLowerCase() &&
              row['id'] is String).toList();
          if (match.isNotEmpty) id = match.first['id'] as String;
        }
      }
      if (!mounted || generation != _generation || _owner() != owner) return;
      if (id == null || !RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id)) {
        setState(() {
          _loading = false;
          _error = 'No verified Spotify artist match was found.';
        });
        return;
      }
      final response = await api.spotifyArtistPage(id);
      if (!mounted || generation != _generation || _owner() != owner) return;
      if (response['kind'] != 'ok' || response['value'] is! Map) {
        setState(() {
          _loading = false;
          _error = 'Spotify artist data is temporarily unavailable.';
        });
        return;
      }
      final value = Map<String, dynamic>.from(response['value'] as Map);
      setState(() {
        _artistId = id;
        _data = value;
        _loading = false;
      });
      unawaited(_refreshFollow(id, owner, generation));
    } catch (_) {
      if (!mounted || generation != _generation || _owner() != owner) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load artist details. Try again.';
      });
    }
  }

  Future<void> _refreshFollow(String id, String owner, int generation) async {
    final key = 'catalog:sp_$id';
    try {
      final api = ref.read(authSessionProvider.notifier).api;
      try {
        await _follows.syncWithCloud(owner, api, ownerStillActive: () =>
            mounted && _owner() == owner && generation == _generation);
      } catch (_) {
        // Preserve the owner-scoped offline follow cache.
      }
      final saved = await _follows.find(owner, key);
      if (!mounted || _owner() != owner || generation != _generation) return;
      setState(() => _following = saved);
    } catch (_) {
      // Artist metadata remains available even when follow storage fails.
    }
  }

  Future<void> _updateFollow({bool? follow, bool? pinned}) async {
    final id = _artistId;
    final owner = _owner();
    if (id == null || owner == null || _savingFollow) return;
    final key = 'catalog:sp_$id';
    final generation = _generation;
    setState(() => _savingFollow = true);
    try {
      if (follow == true) {
        await _follows.follow(owner, key, widget.artistName);
      } else if (follow == false) {
        await _follows.unfollow(owner, key);
      } else if (pinned != null) {
        await _follows.setPinned(owner, key, pinned);
      }
      final record = await _follows.find(owner, key);
      if (mounted && _owner() == owner && generation == _generation) {
        setState(() => _following = record);
      }
      if (mounted && _owner() == owner && generation == _generation) {
        unawaited(_refreshFollow(id, owner, generation));
      }
    } catch (_) {
      if (mounted && _owner() == owner) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not save artist follow status.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _savingFollow = false);
    }
  }

  static List<Map<String, dynamic>> _maps(Object? value) =>
      value is List
          ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
          : [];

  String? _photo() {
    final artist = _data?['artist'];
    if (artist is Map && artist['imageUrl'] is String) {
      return artist['imageUrl'] as String;
    }
    return widget.portraitUrl;
  }

  Widget _section(ThemeData theme, String title, List<Widget> children,
      {String? emptyMessage}) {
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(emptyMessage ?? 'Nothing available yet.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.bzText2)),
          )
        else ...children,
      ]),
    );
  }

  Future<void> _openSpotifyUrl(String? raw) async {
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != 'open.spotify.com') return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to open the catalog attribution link.'),
      ));
    }
  }

  Widget _releaseRow(Map<String, dynamic> release) {
    final url = release['artworkUrl'] as String?;
    final title = release['title'] as String? ?? 'Untitled release';
    final id = release['id'] as String?;
    final date = release['releaseDate'] as String? ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _SpotifyArtwork(url: url, size: 58),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([
        if (date.isNotEmpty) date,
        if (release['type'] is String) release['type'] as String,
      ].join(' · '), maxLines: 1),
      trailing: const BzSvgIcon(name: 'chevron-right', size: 18),
      onTap: id == null ? null : () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SpotifyReleaseScreen(
          albumId: id,
          title: title,
          onTrackSelected: widget.onTrackSelected,
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _data?['artist'];
    final artist = info is Map ? info : const <String, dynamic>{};
    final songs = _maps(_data?['songs']);
    final albums = _maps(_data?['albums']);
    final newReleases = _maps(_data?['newReleases']);
    final suggestions = _data?['searchSuggestions'] is List
        ? (_data!['searchSuggestions'] as List).whereType<String>().toList()
        : <String>[];
    final photo = _photo();
    final title = artist['name'] is String ? artist['name'] as String : widget.artistName;
    final ownerUnchanged = _owner() == _initialOwner;
    final genres = artist['genres'] is List
        ? (artist['genres'] as List).whereType<String>().toList()
        : <String>[];
    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: AppBar(title: const Text('Artist')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Center(child: _SpotifyArtwork(url: photo, size: 152, circle: true)),
                const SizedBox(height: 16),
                Text(title, textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(_data == null ? 'Artist' : 'Artist profile',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.bzText2)),
                const SizedBox(height: 14),
                if (_artistId != null && ownerUnchanged)
                  Wrap(alignment: WrapAlignment.center, spacing: 10, children: [
                    OutlinedButton.icon(
                      onPressed: _savingFollow ? null :
                          () => _updateFollow(follow: _following == null),
                      icon: BzSvgIcon(name: _following == null ? 'user-round-plus' : 'check'),
                      label: Text(_following == null ? 'Follow' : 'Following'),
                    ),
                    if (_following != null)
                      OutlinedButton.icon(
                        onPressed: _savingFollow ? null :
                            () => _updateFollow(pinned: !_following!.isPinned),
                        icon: BzSvgIcon(name: _following!.isPinned ? 'star-filled' : 'star'),
                        label: Text(_following!.isPinned ? 'Unpin' : 'Pin'),
                      ),
                  ]),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(28),
                    child: Center(child: CircularProgressIndicator()))
                else if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 20), child: Column(
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      TextButton(
                        onPressed: _loadArtist,
                        child: const Text('Retry artist lookup'),
                      ),
                    ],
                  )),
                if (_data != null) ...[
                  _section(theme, 'About', [
                    if (genres.isNotEmpty)
                      Text(genres.join(' · ')),
                    if (artist['followers'] is num)
                      Text('${artist['followers']} Spotify followers'),
                    if (genres.isEmpty && artist['followers'] is! num)
                      const Text('Spotify has not provided additional artist biography details.'),
                    TextButton(
                      onPressed: () => _openSpotifyUrl(artist['url'] as String?),
                      child: const Text('Artist details on Spotify'),
                    ),
                  ]),
                  _section(theme, 'Popular Songs', [
                    for (final song in songs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _SpotifyArtwork(
                          url: song['artworkUrl'] as String?, size: 50),
                        title: Text(song['title'] as String? ?? 'Song'),
                        subtitle: Text(song['artist'] as String? ?? title),
                        trailing: const BzSvgIcon(name: 'chevron-right', size: 16),
                        onTap: () => widget.onTrackSelected(song),
                      ),
                  ], emptyMessage: _data?['songStatus'] == 'unavailable'
                      ? 'Song lookup is temporarily unavailable.'
                      : 'Spotify returned no verified artist tracks.'),
                  _section(theme, 'New Releases', [
                    for (final release in newReleases) _releaseRow(release),
                  ], emptyMessage: 'No recent releases verified by Spotify.'),
                  _section(theme, 'Albums & Singles', [
                    for (final release in albums) _releaseRow(release),
                  ], emptyMessage: _data?['albumStatus'] == 'unavailable'
                      ? 'Discography temporarily unavailable.'
                      : 'No releases in the Spotify catalog.'),
                  _section(theme, 'Tours', const [],
                    emptyMessage: 'Spotify does not provide concert or tour schedules through its artist API.'),
                  _section(theme, 'Related Searches', [
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final query in suggestions)
                        ActionChip(label: Text(query),
                          onPressed: () => widget.onSuggestedSearch(query)),
                    ]),
                  ], emptyMessage: 'No additional verified search suggestions available.'),
                ],
                if (widget.savedTracks.isNotEmpty && ownerUnchanged)
                  _section(theme, 'Saved Songs', [
                    for (final track in widget.savedTracks)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _SpotifyArtwork(url: track.artworkUrl, size: 50),
                        title: Text(track.title),
                        subtitle: Text(track.artist),
                        onTap: () => widget.onSavedTrackSelected(track),
                      ),
                  ]),
                const SizedBox(height: 20),
                Text('Artist and release metadata: Spotify. Playback requires an authorized source.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SpotifyReleaseScreen extends ConsumerStatefulWidget {
  final String albumId;
  final String title;
  final ValueChanged<Map<String, dynamic>> onTrackSelected;

  const SpotifyReleaseScreen({
    super.key,
    required this.albumId,
    required this.title,
    required this.onTrackSelected,
  });

  @override
  ConsumerState<SpotifyReleaseScreen> createState() => _SpotifyReleaseScreenState();
}

class _SpotifyReleaseScreenState extends ConsumerState<SpotifyReleaseScreen> {
  Map<String, dynamic>? _album;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final auth = ref.read(authSessionProvider);
    final owner = auth is AuthSignedIn ? auth.userId : null;
    if (owner == null) {
      if (mounted) setState(() => _error = 'Sign in to view albums.');
      return;
    }
    try {
      final response = await ref.read(authSessionProvider.notifier).api
          .spotifyAlbumPage(widget.albumId);
      final latest = ref.read(authSessionProvider);
      if (!mounted || latest is! AuthSignedIn || latest.userId != owner) return;
      setState(() {
        _album = response['kind'] == 'ok' && response['value'] is Map
            ? Map<String, dynamic>.from(response['value'] as Map) : null;
        _error = _album == null ? 'Album data unavailable.' : null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load this album.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = _album?['album'];
    final detail = album is Map ? album : const <String, dynamic>{};
    final raw = _album?['tracks'];
    final tracks = raw is List
        ? raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
        : <Map<String, dynamic>>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: _SpotifyArtwork(
          url: detail['artworkUrl'] as String?, size: 180)),
        const SizedBox(height: 14),
        Text(widget.title, textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall),
        if (detail['releaseDate'] is String)
          Text(detail['releaseDate'] as String, textAlign: TextAlign.center),
        if (_album == null && _error == null)
          const Center(child: Padding(padding: EdgeInsets.all(28),
            child: CircularProgressIndicator())),
        if (_error != null)
          TextButton(onPressed: _load, child: Text('Retry: $_error')),
        if (_album != null) ...[
          const SizedBox(height: 18),
          Text('Songs', style: Theme.of(context).textTheme.titleLarge),
          if (tracks.isEmpty)
            Text(_album?['tracksStatus'] == 'unavailable'
                ? 'Tracks temporarily unavailable.' : 'No tracks returned.'),
          for (final row in tracks)
            ListTile(
              title: Text(row['title'] as String? ?? 'Song'),
              subtitle: Text(row['artist'] as String? ?? 'Artist'),
              onTap: () => widget.onTrackSelected(row),
            ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () async {
              final url = detail['url'];
              final uri = url is String ? Uri.tryParse(url) : null;
              if (uri != null && uri.scheme == 'https' &&
                  uri.host == 'open.spotify.com') {
                await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
              }
            },
            child: const Text('Album source: Spotify'),
          ),
        ],
      ]),
    );
  }
}

class _SpotifyArtwork extends StatelessWidget {
  final String? url;
  final double size;
  final bool circle;
  const _SpotifyArtwork({required this.url, required this.size, this.circle = false});

  @override
  Widget build(BuildContext context) {
    final image = url == null ? null : Uri.tryParse(url!);
    final fallback = Container(
      width: size, height: size, alignment: Alignment.center,
      color: Theme.of(context).bzSurface1,
      child: BzSvgIcon(name: 'mic', size: size * .32),
    );
    final Widget child = image != null && image.scheme == 'https'
        ? Image.network(url!, width: size, height: size,
            fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback)
        : fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(circle ? size / 2 : 10),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}
