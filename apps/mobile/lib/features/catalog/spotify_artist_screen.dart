import 'dart:async';

import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/breezze_navigation.dart';
import '../../app/bootstrap.dart';
import '../../app/followed_artist_store.dart';
import '../../core/auth/auth_session.dart';
import '../../core/database/outbox_sync_service.dart';
import '../../widgets/bz_brand_icons.dart';
import '../../widgets/bz_branded_app_bar.dart';

/// Spotify is the only provider of artist, album, release and track metadata
/// on this page. Tours explicitly report unavailable, rather than pretending
/// another provider's events came from Spotify.
class SpotifyArtistScreen extends ConsumerStatefulWidget {
  final String artistName;
  final String? artistId;
  final String? portraitUrl;
  final List<FavoriteTrack> savedTracks;
  final ValueChanged<Map<String, dynamic>> onTrackSelected;
  final ValueChanged<Map<String, dynamic>> onDeezerAlbumSelected;
  final ValueChanged<FavoriteTrack> onSavedTrackSelected;
  final ValueChanged<String> onSuggestedSearch;

  const SpotifyArtistScreen({
    super.key,
    required this.artistName,
    required this.artistId,
    required this.portraitUrl,
    required this.savedTracks,
    required this.onTrackSelected,
    required this.onDeezerAlbumSelected,
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
  List<Map<String, dynamic>> _tourEvents = [];
  bool _toursLoading = false;
  int _tourRequestGeneration = 0;
  String? _toursMessage;
  String? _concertCountry;
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
      unawaited(_loadTourEvents(
        value['artist'] is Map && value['artist']['name'] is String
            ? value['artist']['name'] as String : widget.artistName,
        owner, generation,
      ));
    } catch (_) {
      if (!mounted || generation != _generation || _owner() != owner) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load artist details. Try again.';
      });
    }
  }

  /// Existing JamBase event service is independent of both music catalogs.
  Future<void> _loadTourEvents(String name, String owner, int generation) async {
    final requestGeneration = ++_tourRequestGeneration;
    // Touring location is a display filter, NEVER a rights/entitlement region.
    final territory = (_concertCountry ??
            ref.read(outboxTerritoryProvider) ?? 'WW')
        .trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(territory) ||
        territory == 'WW' || territory == 'ZZ') {
      if (mounted && generation == _generation && _owner() == owner &&
          requestGeneration == _tourRequestGeneration) {
        setState(() => _toursMessage =
            'Set your country to look for upcoming concerts.');
      }
      return;
    }
    setState(() {
      _toursLoading = true;
      _toursMessage = null;
    });
    try {
      final response = await ref.read(authSessionProvider.notifier).api
          .discoveryConcerts(country: territory);
      if (!mounted || generation != _generation || _owner() != owner ||
          requestGeneration != _tourRequestGeneration) return;
      final raw = response['items'];
      final artist = name.trim().toLowerCase();
      final today = DateTime.now().toUtc();
      final events = raw is List
          ? raw.whereType<Map>().where((item) {
              final performers = item['artist'];
              final date = item['date'];
              final parsed = date is String ? DateTime.tryParse(date) : null;
              return performers is String && parsed != null &&
                  parsed.toUtc().isAfter(today.subtract(const Duration(days: 1))) &&
                  performers.split(',').any((person) =>
                      person.trim().toLowerCase() == artist);
            }).map((item) =>
                Map<String, dynamic>.from(item)).toList()
          : <Map<String, dynamic>>[];
      events.sort((a, b) =>
          (a['date'] as String? ?? '').compareTo(b['date'] as String? ?? ''));
      setState(() {
        _tourEvents = events.take(20).toList();
        _toursLoading = false;
        _toursMessage = events.isEmpty
            ? 'No matching upcoming concerts found in your country.'
            : null;
      });
    } catch (_) {
      if (!mounted || generation != _generation || _owner() != owner ||
          requestGeneration != _tourRequestGeneration) return;
      setState(() {
        _toursLoading = false;
        _toursMessage = 'Concert listings are unavailable right now.';
      });
    }
  }

  Future<void> _changeTourCountry(String artistName) async {
    final current = _concertCountry ?? ref.read(outboxTerritoryProvider) ?? 'WW';
    final country = TextEditingController(
      text: RegExp(r'^[A-Z]{2}$').hasMatch(current) &&
          current != 'WW' ? current : '',
    );
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Concert country'),
        content: TextField(
          controller: country,
          maxLength: 2,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'TZ, KE, US…',
            labelText: 'Two-letter country code',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(country.text),
            child: const Text('Show concerts'),
          ),
        ],
      ),
    );
    country.dispose();
    if (!mounted || selected == null) return;
    final normalized = selected.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(normalized) ||
        normalized == 'WW' || normalized == 'ZZ') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid two-letter country code.'),
      ));
      return;
    }
    final owner = _owner();
    if (owner == null || owner != _initialOwner) return;
    setState(() => _concertCountry = normalized);
    unawaited(_loadTourEvents(artistName, owner, _generation));
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
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
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

  Future<void> _openCatalogSource(String? raw) async {
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' ||
        uri.host != 'open.spotify.com' &&
        uri.host != 'www.deezer.com') return;
    try {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unable to open the catalog attribution link.'),
      ));
    }
  }

  Future<void> _openConcertUrl(Map<String, dynamic> event) async {
    final raw = event['ticketUrl'] is String
        ? event['ticketUrl'] as String
        : event['url'] as String?;
    final url = raw == null ? null : Uri.tryParse(raw);
    if (url == null || url.scheme != 'https') return;
    try {
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Concert link is not available right now.'),
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
      onTap: id == null ? null : () {
        if (release['providerId'] == 'deezer') {
          widget.onDeezerAlbumSelected(release);
          return;
        }
        Navigator.of(context).push(
          breezzePageRoute<void>(
            context: context,builder: (_) => SpotifyReleaseScreen(
            albumId: id,
            title: title,
            onTrackSelected: widget.onTrackSelected,
          )),
        );
      },
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
    final relatedArtists = _maps(_data?['relatedArtists']);
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
      appBar: const BzBrandedAppBar(title: 'Artist'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Center(child: _SpotifyArtwork(
                  url: photo,
                  size: 152,
                  circle: true,
                  semanticLabel: 'Artist portrait for $title',
                )),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(title, textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
                ),
                const SizedBox(height: 6),
                Text(_data == null ? 'Artist' : 'Artist profile',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.bzText2)),
                const SizedBox(height: 14),
                if (_data != null && _artistId != null && ownerUnchanged &&
                    _initialOwner != null)
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
                      Semantics(
                        liveRegion: true,
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
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
                      onPressed: () => _openCatalogSource(artist['url'] as String?),
                      child: const Text('Artist details on Spotify'),
                    ),
                    if (_data?['artistExtra'] is Map) ...[
                      if (artist['followers'] is! num &&
                          (_data!['artistExtra'] as Map)['fans'] is num)
                        Text('Deezer fans: ' +
                            ((_data!['artistExtra'] as Map)['fans'] as num).toInt().toString()),
                      if ((_data!['artistExtra'] as Map)['albumCount'] is num)
                        Text('Deezer catalog albums: ' +
                            ((_data!['artistExtra'] as Map)['albumCount'] as num).toInt().toString()),
                      TextButton(
                        onPressed: () => _openCatalogSource(
                            (_data!['artistExtra'] as Map)['url'] as String?),
                        child: const Text('Additional artist data: Deezer'),
                      ),
                    ],
                  ]),
                  _section(theme, 'Songs', [
                    if (_data?['songSource'] == 'deezer')
                      Text('Deezer catalog · Spotify songs unavailable',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
                    for (final song in songs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _SpotifyArtwork(
                          url: song['artworkUrl'] as String?, size: 50),
                        title: Text(song['title'] as String? ?? 'Song'),
                        subtitle: Text(song['artist'] as String? ?? title),
                        trailing: song['providerId'] == 'deezer'
                            ? IconButton(
                                tooltip: 'Deezer song source',
                                icon: const Icon(Icons.open_in_new, size: 18),
                                onPressed: () => _openCatalogSource(
                                    song['sourceUrl'] as String?),
                              )
                            : const BzSvgIcon(name: 'chevron-right', size: 16),
                        onTap: () => widget.onTrackSelected(song),
                      ),
                  ], emptyMessage: _data?['songStatus'] == 'unavailable'
                      ? 'Song lookup is temporarily unavailable.'
                      : 'Spotify returned no verified artist tracks.'),
                  _section(theme, 'New Releases', [
                    if (_data?['albumSource'] == 'deezer' && newReleases.isNotEmpty)
                      Text('Deezer catalog · Spotify releases unavailable',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
                    for (final release in newReleases) _releaseRow(release),
                  ], emptyMessage: 'No recent releases verified by the selected catalog.'),
                  _section(theme, 'Albums & Singles', [
                    if (_data?['albumSource'] == 'deezer' && albums.isNotEmpty)
                      Text('Deezer catalog · Spotify discography unavailable',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
                    for (final release in albums) _releaseRow(release),
                  ], emptyMessage: _data?['albumStatus'] == 'unavailable'
                      ? 'Discography temporarily unavailable.'
                      : 'No releases in the selected catalog.'),
                  _section(theme, 'Tours', [
                    TextButton.icon(
                      onPressed: () => _changeTourCountry(title),
                      icon: const Icon(Icons.public, size: 18),
                      label: Text('Concert country: ' +
                          ((_concertCountry ?? ref.watch(outboxTerritoryProvider)) == 'WW'
                              ? 'Select'
                              : (_concertCountry ?? ref.watch(outboxTerritoryProvider)))),
                    ),
                    if (_toursLoading)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(),
                      )),
                    if (_toursMessage != null)
                      Text(_toursMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.bzText2,
                        )),
                    for (final event in _tourEvents)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const BzSvgIcon(name: 'calendar', size: 22),
                        title: Text(event['title'] as String? ?? 'Live show'),
                        subtitle: Text([
                          if (event['date'] is String)
                            (event['date'] as String).split('T').first,
                          if (event['venue'] is String) event['venue'] as String,
                          if (event['city'] is String) event['city'] as String,
                        ].join(' · ')),
                        trailing: const BzSvgIcon(name: 'arrow-up-right', size: 18),
                        onTap: () => _openConcertUrl(event),
                      ),
                    if (_tourEvents.isNotEmpty)
                      Text('Concert data provided by JamBase',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.bzText2,
                        )),
                  ], emptyMessage:
                      'Spotify and Deezer do not provide tours in their standard music catalog APIs.'),
                  if (relatedArtists.isNotEmpty)
                    _section(theme, 'Similar Artists', [
                      Text('Deezer artist recommendations · metadata only',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
                      for (final item in relatedArtists)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _SpotifyArtwork(
                            url: item['imageUrl'] as String?, size: 46, circle: true),
                          title: Text(item['name'] as String? ?? 'Artist'),
                          trailing: const BzSvgIcon(name: 'chevron-right', size: 18),
                          onTap: item['name'] is String
                              ? () => widget.onSuggestedSearch(item['name'] as String)
                              : null,
                        ),
                    ]),
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
                Text(_data?['sourceMatch'] == 'unique_exact_name'
                    ? 'Artist identity: Spotify. Supplemental sections: Deezer where indicated. Playback requires an authorized source.'
                    : 'Artist and release metadata: Spotify. Playback requires an authorized source.',
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
      appBar: BzBrandedAppBar(title: widget.title),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: _SpotifyArtwork(
          url: detail['artworkUrl'] as String?,
          size: 180,
          semanticLabel: 'Cover artwork for ${widget.title}',
        )),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(widget.title, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall),
        ),
        if (detail['releaseDate'] is String)
          Text(detail['releaseDate'] as String, textAlign: TextAlign.center),
        if (_album == null && _error == null)
          const Center(child: Padding(padding: EdgeInsets.all(28),
            child: CircularProgressIndicator())),
        if (_error != null)
          TextButton(onPressed: _load, child: Text('Retry: $_error')),
        if (_album != null) ...[
          const SizedBox(height: 18),
          Semantics(
            header: true,
            child: Text('Songs', style: Theme.of(context).textTheme.titleLarge),
          ),
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
  /// Only hero artwork needs a separate image announcement; nearby text
  /// already names the item represented by list-row thumbnails.
  final String? semanticLabel;
  const _SpotifyArtwork({
    required this.url,
    required this.size,
    this.circle = false,
    this.semanticLabel,
  });

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
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
        : fallback;
    final visual = ClipRRect(
      borderRadius: BorderRadius.circular(circle ? size / 2 : 10),
      child: SizedBox(width: size, height: size, child: child),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: visual);
    }
    return Semantics(
      image: true,
      label: semanticLabel!,
      child: ExcludeSemantics(child: visual),
    );
  }
}
