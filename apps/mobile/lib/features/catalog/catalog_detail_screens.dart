import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/breezze_navigation.dart';
import '../../app/bootstrap.dart';
import '../search/search_screen.dart';
import 'spotify_artist_screen.dart';
import '../../app/saved_album_store.dart';
import '../../core/audio/playback_source_policy.dart';
import '../video/open_youtube_player.dart';
import '../../core/auth/auth_session.dart';
import '../../core/database/outbox_sync_service.dart';
import '../../features/player/player_controller.dart';
import '../../widgets/bz_brand_icons.dart';
import '../../widgets/bz_branded_app_bar.dart';

final _deezerTrackMatchesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, query) async {
  final data = await ref
      .read(authSessionProvider.notifier)
      .api
      .discoveryTrackSearch(query);
  final rawItems = data['items'];
  if (rawItems is! List) return const [];
  return rawItems.whereType<Map>().map((item) =>
      item.map((key, value) => MapEntry(key.toString(), value))).toList();
});

final _deezerAlbumTracksProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, albumId) async {
  return ref
      .read(authSessionProvider.notifier)
      .api
      .discoveryAlbumTracks(albumId);
});

/// Track details use only metadata returned by the active search source.
/// The album relationship remains unavailable until a canonical album catalog is connected.
class TrackDetailScreen extends ConsumerWidget {
  final TrackInfo track;
  final List<TrackInfo> relatedTracks;
  final String origin;

  const TrackDetailScreen({
    super.key,
    required this.track,
    this.relatedTracks = const [],
    this.origin = 'search',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authSessionProvider);
    final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
    final favoriteKey = (ownerId: ownerId, trackId: track.id);
    final favoriteState = ref.watch(isTrackFavoriteProvider(favoriteKey));
    final artistName = track.artist ?? 'Unknown artist';
    final trackTitle = track.title ?? 'Unknown track';
    final appleTrackMatches = ref.watch(_deezerTrackMatchesProvider('$trackTitle $artistName'));
    final artistTracks = relatedTracks
        .where((item) => (item.artist ?? '').trim().toLowerCase() == artistName.trim().toLowerCase())
        .toList();
    final queueTracks = (relatedTracks.isEmpty ? [track] : relatedTracks)
        .where((item) =>
            !isMetadataOnlyTrackId(item.id))
        .toList();
    final queue = [
      for (final item in queueTracks)
        TrackInfo(
          id: item.id,
          title: item.title,
          artist: item.artist,
          artworkUrl: item.artworkUrl,
          duration: item.duration,
        ),
    ];
    final selectedIndex = queueTracks.indexWhere((item) => item.id == track.id);

    Future<void> toggleLibrary() async {
      // Never apply a stale song-detail action to an account that signed out
      // or switched while this route remained in the navigation stack.
      final current = ref.read(authSessionProvider);
      if ((current is AuthSignedIn ? current.userId : 'guest') != ownerId) {
        return;
      }
      try {
        final saved = await ref.read(favoritesStoreProvider).toggle(
          FavoriteTrack(
            id: track.id,
            title: trackTitle,
            artist: artistName,
            artworkUrl: track.artworkUrl,
            durationMs: track.duration.inMilliseconds,
          ),
          ownerId: ownerId,
        );
        if (!context.mounted) return;
        ref.invalidate(isTrackFavoriteProvider(favoriteKey));
        ref.read(favoritesRefreshProvider.notifier).state++;
        try {
          await ref.read(outboxSyncProvider).drainIfSignedIn();
        } catch (_) {
          // The local favorite and outbox are already durable. Failed cloud
          // delivery must not turn a successful local edit into a UI error.
        }
        if (!context.mounted) return;
        final latest = ref.read(authSessionProvider);
        if ((latest is AuthSignedIn ? latest.userId : 'guest') != ownerId) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(saved
              ? 'Saved to Library on this device'
              : 'Removed from Library on this device'),
        ));
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update Library.')),
          );
        }
      }
    }

    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: BzBrandedAppBar(
        title: 'Song',
        leading: IconButton(
          tooltip: 'Back to search',
          icon: const BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: BzAmbientBackdrop(
              // Content is the colour (§1): the artwork blooms softly
              // behind the hero zone while sections below stay on the
              // plain ground.
              artworkUrl: track.artworkUrl,
              child: ListView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, BzBreakpoints.bottomClearance(context, compact: 180)),
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(BzRadius.artwork),
                    child: _TrackArtwork(url: track.artworkUrl, size: 260),
                  ),
                ),
                const SizedBox(height: 22),
                Text(trackTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(artistName, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: theme.bzText2)),
                const SizedBox(height: 6),
                Text(
                  track.id.startsWith('bz:')
                      ? 'Track metadata from the connected music source'
                      : 'Track from your Breezze library',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                ),
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: !canOfferPlaybackAction(track.id)
                          ? null
                          : () async {
                        if (isYouTubeSongId(track.id)) {
                          await openYouTubePlayer(
                            context: context,
                            ref: ref,
                            videoId: track.id.substring('bz:youtube_music:'.length),
                            title: trackTitle,
                            artist: artistName,
                            artworkUrl: track.artworkUrl,
                          );
                          return;
                        }
                        await ref.read(playerControllerProvider.notifier).playTrack(
                          trackId: track.id,
                          queue: queue,
                          startIndex: selectedIndex < 0 ? 0 : selectedIndex,
                          origin: origin,
                          sourceContext: 'Song details',
                        );
                      },
                      icon: BzSvgIcon(name: 'play', color: theme.bzBackground, size: 18),
                      label: Text(isYouTubeSongId(track.id)
                          ? 'Watch on YouTube'
                          : !canOfferPlaybackAction(track.id)
                              ? 'Full audio unavailable in Breezze'
                              : 'Play'),
                    ),
                    OutlinedButton.icon(
                      // Never display an actionable-looking "Add" state
                      // before the native owner-scoped favorite lookup ends.
                      // The button remains disabled on lookup failure.
                      onPressed: favoriteState.isLoading ||
                              favoriteState.hasError
                          ? null
                          : toggleLibrary,
                      icon: BzSvgIcon(name:
                          favoriteState.valueOrNull == true ? 'check' : 'plus'),
                      label: Text(favoriteState.isLoading
                          ? 'Checking Library...'
                          : favoriteState.hasError
                              ? 'Library unavailable'
                              : favoriteState.valueOrNull == true
                                  ? 'Remove from Library'
                                  : 'Add to Library'),
                    ),
                    OutlinedButton.icon(
                      onPressed: isMetadataOnlyTrackId(track.id)
                          ? null
                          : () => ref.read(playerControllerProvider.notifier).playNext(
                                TrackInfo(id: track.id, title: track.title, artist: track.artist, artworkUrl: track.artworkUrl, duration: track.duration),
                                origin: origin,
                                sourceContext: 'Song details',
                              ),
                      icon: const BzSvgIcon(name: 'list-music'),
                      label: const Text('Play Next'),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                _CatalogSection(
                  title: 'Artist',
                  subtitle: 'Artist metadata is supplied by the track search result. This is not a verified artist profile.',
                  available: true,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: theme.bzSurface1, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: BzSvgIcon(name: 'mic', color: theme.bzText2, size: 22),
                    ),
                    title: Text(artistName),
                    subtitle: const Text('Open artist page'),
                    trailing: const BzSvgIcon(name: 'chevron-right', size: 18),
                    onTap: () => Navigator.of(context).push(breezzePageRoute<void>(
            context: context,
                      builder: (_) => ArtistDetailScreen(
                        artist: artistName,
                        savedTracks: const [],
                        searchTracks: [
                          for (final item in artistTracks)
                            FavoriteTrack(
                              id: item.id,
                              title: item.title ?? 'Unknown track',
                              artist: item.artist ?? artistName,
                              artworkUrl: item.artworkUrl,
                              durationMs: item.duration.inMilliseconds,
                            ),
                        ],
                      ),
                    )),
                  ),
                ),
                appleTrackMatches.when(
                  loading: () => _CatalogSection(
                    title: 'Album',
                    subtitle: 'Checking the Deezer catalog for an exact track-to-album relationship.',
                    available: true,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (_, __) => _CatalogSection(
                    title: 'Album',
                    subtitle: 'The Deezer catalog could not verify an album relationship for this track.',
                    available: false,
                  ),
                  data: (matches) {
                    final exact = matches.where((item) {
                      final title = item['title'];
                      final artist = item['artist'];
                      return title is String &&
                          artist is String &&
                          title.trim().toLowerCase() == trackTitle.trim().toLowerCase() &&
                          artist.trim().toLowerCase() == artistName.trim().toLowerCase() &&
                          item['albumId'] != null;
                    }).toList();
                    if (exact.isEmpty) {
                      return _CatalogSection(
                        title: 'Album',
                        subtitle: 'No exact Deezer catalog track match was found. Breezze will not infer an album from similar titles or artist names.',
                        available: false,
                      );
                    }
                    final album = exact.first;
                    return _CatalogSection(
                      title: 'Verified album relationship',
                      subtitle: 'Exact title and artist match from Deezer catalog metadata.',
                      available: true,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _TrackArtwork(
                          url: album['artworkUrl'] as String?,
                          size: 56,
                        ),
                        title: Text(album['albumTitle'] as String? ?? 'Unknown album'),
                        subtitle: Text(
                          [
                            if (album['releaseDate'] is String)
                              (album['releaseDate'] as String).split('T').first,
                            'Deezer catalog',
                          ].join(' · '),
                        ),
                        trailing: const BzSvgIcon(name: 'arrow-up-right', size: 19),
                        onTap: () {
                          final albumId = album['albumId'];
                          if (albumId == null) return;
                          Navigator.of(context).push(breezzePageRoute<void>(
            context: context,
                            builder: (_) => DeezerAlbumCatalogScreen(
                              albumId: albumId.toString(),
                              title: album['albumTitle'] as String? ?? 'Unknown album',
                              artist: album['artist'] as String? ?? artistName,
                              artworkUrl: album['artworkUrl'] as String?,
                              deezerUrl: album['albumUrl'] as String?,
                            ),
                          ));
                        },
                      ),
                    );
                  },
                ),
                _CatalogSection(
                  title: 'Track information',
                  subtitle: 'Duration: ' + (track.duration > Duration.zero ? _formatDuration(track.duration) : 'Not provided'),
                  available: true,
                  child: Text('Metadata supplied by the connected catalog.', style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return duration.inMinutes.toString() + ':' + seconds;
  }
}

/// Single Breezze artist page; Spotify is the exclusive artist catalogue.
/// Older saved artist references resolve by exact name on Spotify instead of
/// fetching a parallel Deezer profile or pretending two artists are the same.
class ArtistDetailScreen extends ConsumerWidget {
  final String artist;
  final List<FavoriteTrack> savedTracks;
  final List<FavoriteTrack> searchTracks;
  final String? canonicalArtistId;
  final String? portraitUrl;
  final String? spotifyArtistId;

  const ArtistDetailScreen({
    super.key,
    required this.artist,
    required this.savedTracks,
    this.searchTracks = const [],
    this.canonicalArtistId,
    this.portraitUrl,
    this.spotifyArtistId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SpotifyArtistScreen(
      artistName: artist,
      artistId: spotifyArtistId,
      portraitUrl: spotifyArtistId == null ? null : portraitUrl,
      savedTracks: savedTracks,
      onTrackSelected: (row) {
        final id = row['providerTrackId'];
        final provider = row['providerId'] == 'deezer' ? 'deezer' : 'spotify';
        if (id is! String ||
            !(provider == 'deezer'
                ? RegExp(r'^[0-9]{1,20}$').hasMatch(id)
                : RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id))) return;
        final duration = row['durationSec'];
        final track = TrackInfo(
          id: 'bz:$provider:$id',
          title: row['title'] as String? ?? 'Song',
          artist: row['artist'] as String? ?? artist,
          artworkUrl: row['artworkUrl'] as String?,
          duration: Duration(seconds: duration is num ? duration.toInt() : 0),
        );
        Navigator.of(context).push(breezzePageRoute<void>(
            context: context,
          builder: (_) => TrackDetailScreen(track: track),
        ));
      },
      onDeezerAlbumSelected: (release) {
        final id = release['id'];
        if (id is! String || !RegExp(r'^[0-9]{1,20}$').hasMatch(id)) return;
        Navigator.of(context).push(breezzePageRoute<void>(
          context: context,
          builder: (_) => DeezerAlbumCatalogScreen(
            albumId: id,
            title: release['title'] as String? ?? 'Album',
            artist: artist,
            artworkUrl: release['artworkUrl'] as String?,
            deezerUrl: release['url'] as String?,
          ),
        ));
      },
      onSavedTrackSelected: (favorite) {
        Navigator.of(context).push(breezzePageRoute<void>(
            context: context,
          builder: (_) => TrackDetailScreen(track: favorite.toTrackInfo()),
        ));
      },
      onSuggestedSearch: (query) {
        Navigator.of(context).push(breezzePageRoute<void>(
            context: context,
          builder: (_) => SearchScreen(initialQuery: query),
        ));
      },
    );
  }
}

/// Deezer album detail from the public album and track API.
/// It never turns a preview URL into a full-track playback source.
class DeezerAlbumCatalogScreen extends ConsumerWidget {
  final String albumId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? deezerUrl;

  const DeezerAlbumCatalogScreen({
    super.key,
    required this.albumId,
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.deezerUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authSessionProvider);
    final ownerId = auth is AuthSignedIn ? auth.userId : 'guest';
    final savedKey = (ownerId: ownerId, albumId: albumId);
    final isSaved = ref.watch(isAlbumSavedProvider(savedKey));
    final isPinned = ref.watch(isAlbumPinnedProvider(savedKey));
    final tracks = ref.watch(_deezerAlbumTracksProvider(albumId));
    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: BzBrandedAppBar(
        title: 'Album',
        leading: IconButton(
          tooltip: 'Back',
          icon: const BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: tracks.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BzSvgIcon(name: 'wifi-off', size: 34),
                      const SizedBox(height: 12),
                      Text('Album catalog unavailable', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('Deezer could not return this album tracklist.', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref.invalidate(_deezerAlbumTracksProvider(albumId)),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (data) {
                final rawAlbum = data['album'];
                final albumMetadata = rawAlbum is Map
                    ? Map<String, dynamic>.from(rawAlbum)
                    : <String, dynamic>{};
                final albumGenres = albumMetadata['genres'] is List
                    ? (albumMetadata['genres'] as List)
                        .whereType<String>()
                        .where((value) => value.trim().isNotEmpty)
                        .toList(growable: false)
                    : <String>[];
                final isCompilation = albumMetadata['isCompilation'] == true;
                final rawItems = data['items'];
                final items = rawItems is List
                    ? rawItems.whereType<Map>().map((item) =>
                        item.map((key, value) => MapEntry(key.toString(), value))).toList()
                    : <Map<String, dynamic>>[];
                return BzAmbientBackdrop(
                  artworkUrl: artworkUrl,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, BzBreakpoints.bottomClearance(context, compact: 180)),
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(BzRadius.artwork),
                          child: artworkUrl == null
                              ? Container(
                                  width: 220,
                                  height: 220,
                                  color: theme.bzSurface1,
                                  alignment: Alignment.center,
                                  child: const BzBnoteMark(size: 72),
                                )
                              : Image.network(
                                  artworkUrl!,
                                  width: 220,
                                  height: 220,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const BzBnoteMark(size: 72),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 6),
                      Text(artist, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: theme.bzText2)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: isSaved.isLoading ? null : () async {
                          try {
                            final wasSaved = isSaved.valueOrNull == true;
                            final store = SavedAlbumStore();
                            if (wasSaved) {
                              await store.remove(ownerId, albumId);
                            } else {
                              await store.save(ownerId, SavedAlbum(
                                id: albumId,
                                title: title,
                                artist: artist,
                                artworkUrl: artworkUrl,
                                catalogUrl: deezerUrl,
                                genres: albumGenres,
                                isCompilation: isCompilation,
                                addedAt: DateTime.now().toUtc(),
                              ));
                            }
                            var cloudSynced = false;
                            final active = context.mounted
                                ? ref.read(authSessionProvider)
                                : null;
                            if (auth is AuthSignedIn &&
                                active is AuthSignedIn &&
                                active.userId == ownerId) {
                              try {
                                await store.syncWithCloud(
                                  ownerId,
                                  ref.read(authSessionProvider.notifier).api,
                                  ownerStillActive: () {
                                    if (!context.mounted) return false;
                                    final latest = ref.read(authSessionProvider);
                                    return latest is AuthSignedIn &&
                                        latest.userId == ownerId;
                                  },
                                );
                                cloudSynced = true;
                              } catch (_) {
                                // The durable local outbox retains this exact
                                // add/remove operation for the next reconnect.
                              }
                            }
                            ref.invalidate(isAlbumSavedProvider(savedKey));
                            ref.invalidate(isAlbumPinnedProvider(savedKey));
                            ref.read(savedAlbumRefreshProvider.notifier).state++;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(
                                  auth is! AuthSignedIn
                                      ? (wasSaved ? 'Removed from this device'
                                          : 'Saved on this device')
                                      : cloudSynced
                                          ? (wasSaved ? 'Album removed from Library'
                                              : 'Album saved across your devices')
                                          : 'Saved locally. Cloud sync will retry when connected.',
                                )),
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Could not update saved albums.')),
                              );
                            }
                          }
                        },
                        icon: BzSvgIcon(
                          name: isSaved.valueOrNull == true ? 'check' : 'plus',
                          color: theme.bzBackground,
                        ),
                        label: Text(isSaved.valueOrNull == true
                            ? 'Saved in Library'
                            : 'Add Album to Library'),
                      ),
                      if (isSaved.valueOrNull == true) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: isPinned.isLoading ? null : () async {
                            final active = ref.read(authSessionProvider);
                            final activeOwner = active is AuthSignedIn
                                ? active.userId : 'guest';
                            if (activeOwner != ownerId) return;
                            try {
                              final store = SavedAlbumStore();
                              final nextPinned = isPinned.valueOrNull != true;
                              final updated = await store.setPinned(
                                ownerId, albumId, nextPinned,
                              );
                              if (!updated || !context.mounted) return;
                              var synced = active is! AuthSignedIn;
                              if (active is AuthSignedIn) {
                                try {
                                  await store.syncWithCloud(
                                    ownerId,
                                    ref.read(authSessionProvider.notifier).api,
                                    ownerStillActive: () {
                                      if (!context.mounted) return false;
                                      final current = ref.read(authSessionProvider);
                                      return current is AuthSignedIn &&
                                          current.userId == ownerId;
                                    },
                                  );
                                  synced = true;
                                } catch (_) {
                                  // Pin remains durable locally when offline.
                                }
                              }
                              if (!context.mounted) return;
                              final latest = ref.read(authSessionProvider);
                              if ((latest is AuthSignedIn
                                  ? latest.userId : 'guest') != ownerId) return;
                              ref.invalidate(isAlbumPinnedProvider(savedKey));
                              ref.read(savedAlbumRefreshProvider.notifier).state++;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(synced
                                    ? (nextPinned ? 'Album pinned to top'
                                        : 'Album unpinned')
                                    : 'Pin saved on this device. Cloud sync will retry.')),
                              );
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content:
                                      Text('Could not update album pin.')),
                                );
                              }
                            }
                          },
                          icon: BzSvgIcon(name:
                              isPinned.valueOrNull == true ? 'star-filled' : 'star'),
                          label: Text(isPinned.valueOrNull == true
                              ? 'Unpin album' : 'Pin album to top'),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.bzSurface1,
                          borderRadius: BorderRadius.circular(BzRadius.card),
                          border: Border.all(color: theme.bzSeparator),
                        ),
                        child: Text(
                          'Deezer album metadata and short audio previews. These are not full recordings; full-track and offline playback require separately authorized rights.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text('Tracks • ${items.length}', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (items.isEmpty)
                        Text('Deezer did not return tracks for this album.', style: theme.textTheme.bodyMedium)
                      else
                        for (var i = 0; i < items.length; i++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: SizedBox(
                              width: 28,
                              child: Text(
                                (items[i]['trackNumber'] ?? i + 1).toString().padLeft(2, '0'),
                                style: theme.textTheme.labelMedium?.copyWith(color: theme.bzText2),
                              ),
                            ),
                            title: Text(items[i]['title'] as String? ?? 'Unknown track', maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              items[i]['durationMs'] is num
                                  ? _formatDuration(Duration(milliseconds: (items[i]['durationMs'] as num).toInt()))
                                  : 'Duration not supplied',
                            ),
                            trailing: IconButton(
                              tooltip: items[i]['previewUrl'] is String
                                  ? 'Play 30-second sample in Breezze' : 'Full audio unavailable in Breezze',
                              icon: BzSvgIcon(name: items[i]['previewUrl'] is String
                                  ? 'play' : 'info', size: 18),
                              onPressed: () async {
                                final item = items[i];
                                final trackId = item['id']?.toString() ?? '';
                                if (item['previewUrl'] is String &&
                                    RegExp(r'^[0-9]{1,20}$').hasMatch(trackId)) {
                                  final id = 'bz:deezer_preview:$trackId';
                                  await ref.read(playerControllerProvider.notifier).playTrack(
                                    trackId: id,
                                    queue: [TrackInfo(
                                      id: id,
                                      title: item['title'] as String?,
                                      artist: artist,
                                      artworkUrl: artworkUrl,
                                      duration: const Duration(seconds: 30),
                                    )],
                                    startIndex: 0,
                                    origin: 'album',
                                    sourceContext: 'Deezer preview (up to 30 seconds)',
                                  );
                                } else if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text(
                                      'Full audio is unavailable in Breezze until a licensed stream is connected.',
                                    )),
                                  );
                                }
                              },
                            ),
                          ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Album detail layout. Construct this only from a verified canonical album
/// record; search-result tracks alone are not enough to synthesize an album.
class AlbumDetailScreen extends ConsumerWidget {
  final String canonicalAlbumId;
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? releaseDate;
  final String? recordLabel;
  final List<TrackInfo> tracks;
  final List<String> credits;

  const AlbumDetailScreen({
    super.key,
    required this.canonicalAlbumId,
    required this.title,
    required this.artist,
    required this.tracks,
    this.artworkUrl,
    this.releaseDate,
    this.recordLabel,
    this.credits = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queue = tracks.where((track) => !isMetadataOnlyTrackId(track.id)).toList();

    Future<void> playAt(int index, {bool shuffle = false}) async {
      if (tracks.isEmpty || index < 0 || index >= tracks.length) return;
      final track = tracks[index];
      if (isYouTubeSongId(track.id)) {
        await openYouTubePlayer(
          context: context,
          ref: ref,
          videoId: track.id.substring('bz:youtube_music:'.length),
          title: track.title ?? 'YouTube Music',
          artist: track.artist ?? artist,
          artworkUrl: track.artworkUrl,
        );
        return;
      }
      if (isMetadataOnlyTrackId(track.id)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This album track has metadata only; native playback is unavailable.')),
        );
        return;
      }
      final queueIndex = queue.indexWhere((item) => item.id == track.id);
      if (queueIndex < 0) return;
      final player = ref.read(playerControllerProvider.notifier);
      await player.playTrack(
        trackId: track.id,
        queue: queue,
        startIndex: queueIndex,
        origin: 'album',
        sourceContext: canonicalAlbumId,
      );
      if (shuffle) player.toggleShuffle();
    }

    Future<void> play({bool shuffle = false}) async {
      if (tracks.isEmpty) return;
      final nativeIndex = tracks.indexWhere((item) => !isMetadataOnlyTrackId(item.id));
      if (nativeIndex >= 0) {
        await playAt(nativeIndex, shuffle: shuffle);
      } else {
        await playAt(0, shuffle: shuffle);
      }
    }

    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: BzBrandedAppBar(
        title: 'Album',
        leading: IconButton(
          tooltip: 'Back',
          icon: const BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: BzAmbientBackdrop(
              artworkUrl: artworkUrl,
              child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(BzRadius.artwork),
                    child: _TrackArtwork(
                      url: artworkUrl,
                      size: 250,
                      radius: BzRadius.artwork,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(artist,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.bzText2,
                    )),
                if (releaseDate != null || recordLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [if (releaseDate != null) releaseDate!, if (recordLabel != null) recordLabel!].join(' · '),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: queue.isEmpty ? null : () => play(),
                      icon: BzSvgIcon(name: 'play', color: theme.bzBackground, size: 18),
                      label: const Text('Play'),
                    ),
                    OutlinedButton.icon(
                      onPressed: queue.isEmpty ? null : () => play(shuffle: true),
                      icon: const BzSvgIcon(name: 'shuffle'),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                _CatalogSection(
                  title: 'Tracks',
                  subtitle: 'The verified tracklist for this album.',
                  available: tracks.isNotEmpty,
                  child: Column(
                    children: [
                      for (var i = 0; i < tracks.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text(
                            '${i + 1}'.padLeft(2, '0'),
                            style: theme.textTheme.labelMedium?.copyWith(color: theme.bzText2),
                          ),
                          title: Text(
                            tracks[i].title ?? 'Unknown track',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            tracks[i].artist ?? artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            _duration(tracks[i].duration),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                          ),
                          onTap: () => playAt(i),
                        ),
                    ],
                  ),
                ),
                _CatalogSection(
                  title: 'Credits',
                  subtitle: 'Verified album and track credits.',
                  available: credits.isNotEmpty,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final credit in credits) Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(credit),
                    )],
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  String _duration(Duration duration) {
    if (duration <= Duration.zero) return '';
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _CatalogSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool available;
  final Widget? child;

  const _CatalogSection({
    required this.title,
    required this.subtitle,
    required this.available,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (available && child != null)
            child!
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.bzSurface1,
                borderRadius: BorderRadius.circular(BzRadius.card),
                border: Border.all(color: theme.bzSeparator),
              ),
              child: Row(
                children: [
                  const BzSvgIcon(name: 'info', size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
class _TrackArtwork extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;

  const _TrackArtwork({
    required this.url,
    required this.size,
    this.radius = BzRadius.artwork,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? Container(
              width: size,
              height: size,
              color: theme.bzSurface1,
              alignment: Alignment.center,
              child: BzBnoteMark(size: size * 0.3, color: theme.bzText2),
            )
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: size,
                height: size,
                color: theme.bzSurface1,
                alignment: Alignment.center,
                child: BzBnoteMark(size: size * 0.3, color: theme.bzText2),
              ),
            ),
    );
  }
}
