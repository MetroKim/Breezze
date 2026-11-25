import 'dart:async';

import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart' show FavoriteTrack;
import '../../app/playlist_store.dart';
import '../../core/audio/playback_source_policy.dart';
import '../../core/auth/auth_session.dart';
import '../../widgets/bz_brand_icons.dart';
import '../player/player_controller.dart';
import '../video/open_youtube_player.dart';

/// A guest playlist is local; a private playlist belongs only to the active
/// signed-in account. Transitional auth states expose neither owner's data.
bool playlistOwnerMatchesSession(String ownerId, AuthState auth) =>
    ownerId == 'guest'
        ? auth is AuthSignedOut || auth is AuthUninitialized
        : auth is AuthSignedIn && auth.userId == ownerId;

/// Detail view for a device-local Breezze playlist.
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String ownerId;
  final String playlistId;
  final VoidCallback? onChanged;

  const PlaylistDetailScreen({
    super.key,
    required this.ownerId,
    required this.playlistId,
    this.onChanged,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final _store = PlaylistStore();
  UserPlaylist? _playlist;
  bool _loading = true;
  bool _remoteSynced = false;

  /// A mounted playlist route must never reveal account A's cached data
  /// after a logout, login or account switch to B.
  bool _ownerStillActive() {
    if (!mounted) return false;
    final auth = ref.read(authSessionProvider);
    return playlistOwnerMatchesSession(widget.ownerId, auth);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _sync() async {
    final auth = ref.read(authSessionProvider);
    if (auth is! AuthSignedIn || auth.userId != widget.ownerId) return;
    await _store.syncOwner(
      widget.ownerId,
      ref.read(authSessionProvider.notifier).api,
      ownerStillActive: () {
        if (!mounted) return false;
        final current = ref.read(authSessionProvider);
        return current is AuthSignedIn && current.userId == widget.ownerId;
      },
    );
  }

  Future<void> _load({bool sync = true}) async {
    if (!_ownerStillActive()) return;
    if (sync) await _sync();
    if (!_ownerStillActive()) return;
    var playlists = await _store.load(widget.ownerId);
    if (!_ownerStillActive()) return;
    var remoteSynced = false;
    final auth = ref.read(authSessionProvider);
    final hasPending = await _store.pendingCount(
      widget.ownerId, playlistId: widget.playlistId,
    ) > 0;
    if (auth is AuthSignedIn &&
        auth.userId == widget.ownerId &&
        !hasPending &&
        RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(widget.playlistId)) {
      try {
        final remote = await ref.read(authSessionProvider.notifier).api.getPlaylist(widget.playlistId);
        final rawItems = remote['items'];
        final tracks = <FavoriteTrack>[];
        if (rawItems is List) {
          for (final raw in rawItems) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            final rawTrack = item['track'];
            if (rawTrack is! Map) continue;
            final track = Map<String, dynamic>.from(rawTrack);
            final artist = track['artist'];
            tracks.add(FavoriteTrack(
              id: track['id'] as String? ?? item['trackId'] as String? ?? '',
              title: track['title'] as String? ?? '',
              artist: artist is Map ? artist['name'] as String? ?? '' : '',
              durationMs: ((track['duration'] as num?)?.toInt() ?? 0) * 1000,
            ));
          }
        }
        // The remote request may have outlived a logout or user switch.
        // Do not write its response to a private local cache in that case.
        if (!_ownerStillActive()) return;
        remoteSynced = await _store.replaceTracks(
          widget.ownerId, widget.playlistId, tracks,
        );
        playlists = await _store.load(widget.ownerId);
      } catch (_) {
        // Preserve the last locally cached playlist while offline.
      }
    }
    if (!_ownerStillActive()) return;
    setState(() {
      final matches = playlists.where((item) => item.id == widget.playlistId).toList();
      _playlist = matches.isEmpty ? null : matches.first;
      _remoteSynced = remoteSynced;
      _loading = false;
    });
  }

  List<TrackInfo> _queue(UserPlaylist playlist) => [
        for (final item in playlist.tracks)
          if (canQueueTrackId(item.id)) item.toTrackInfo(),
      ];

  Future<void> _playAll(UserPlaylist playlist) async {
    if (!_ownerStillActive() || playlist.tracks.isEmpty) return;
    final nativeIndex = playlist.tracks.indexWhere((item) => canQueueTrackId(item.id));
    if (nativeIndex >= 0) {
      if (playlist.tracks.any((item) => !canQueueTrackId(item.id)) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Catalogue-only tracks are excluded from native playback; only playable tracks enter the queue.')),
        );
      }
      await _playTrack(playlist, nativeIndex);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(playlist.tracks.any((item) =>
              isYouTubeSongId(item.id) || item.id.startsWith('bzv:'))
              ? 'Tap a YouTube song to watch it in the official player. Native Play All is unavailable for these tracks.'
              : 'This playlist contains no currently playable songs.')),
      );
    }
  }

  Future<void> _playTrack(UserPlaylist playlist, int index) async {
    if (!_ownerStillActive()) return;
    final track = playlist.tracks[index];
    // The saved playlist can keep YouTube Music tracks as library entries,
    // but their playback is through the official foreground video surface.
    // They must never enter the native audio queue or offline download path.
    final youtubeVideoId = isYouTubeSongId(track.id)
        ? track.id.substring('bz:youtube_music:'.length)
        : track.id.startsWith('bzv:')
            ? track.id.substring(4)
            : null;
    if (youtubeVideoId != null && canOfferPlaybackAction(track.id)) {
      await openYouTubePlayer(
        context: context,
        ref: ref,
        videoId: youtubeVideoId,
        title: track.title,
        artist: track.artist,
        artworkUrl: track.artworkUrl,
      );
      return;
    }
    if (!canQueueTrackId(track.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This playlist item has metadata only; native playback is unavailable.')),
        );
      }
      return;
    }
    final queue = _queue(playlist);
    final queueIndex = queue.indexWhere((item) => item.id == track.id);
    if (queueIndex < 0) return;
    await ref.read(playerControllerProvider.notifier).playTrack(
          trackId: track.id,
          queue: queue,
          startIndex: queueIndex,
          origin: 'playlist',
          sourceContext: playlist.name,
        );
  }

  Future<void> _rename(UserPlaylist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!_ownerStillActive() || name == null || name.trim().isEmpty) return;
    await _store.rename(widget.ownerId, playlist.id, name);
    await _load(sync: false);
    unawaited(_sync());
    widget.onChanged?.call();
  }

  Future<void> _delete(UserPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(widget.ownerId == 'guest'
          ? '“${playlist.name}” will be removed from this device.'
          : '“${playlist.name}” will be removed here and deleted from your other devices when synchronization completes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_ownerStillActive()) return;
    await _store.delete(widget.ownerId, playlist.id);
    unawaited(_sync());
    widget.onChanged?.call();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Watching auth ensures a previously opened private route is immediately
    // replaced on sign-out or account switch, even if it has loaded artwork.
    final auth = ref.watch(authSessionProvider);
    if (!playlistOwnerMatchesSession(widget.ownerId, auth)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Playlist unavailable')),
        body: const Center(
          child: Text('This playlist is not available in the current account.'),
        ),
      );
    }
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        backgroundColor: theme.bzBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final playlist = _playlist;
    if (playlist == null) {
      return Scaffold(
        backgroundColor: theme.bzBackground,
        appBar: AppBar(
          leading: IconButton(
            icon: BzSvgIcon(name: 'chevron-down'),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text('Playlist'),
        ),
        body: const Center(child: Text('This playlist is no longer available.')),
      );
    }

    final artworks = playlist.tracks
        .where((item) => item.artworkUrl != null)
        .map((item) => item.artworkUrl!)
        .toList();
    final artwork = artworks.isEmpty ? null : artworks.first;

    return Scaffold(
      backgroundColor: theme.bzBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close playlist',
                      icon: BzSvgIcon(name: 'chevron-down'),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: BzSvgIcon(name: 'more-vertical'),
                      onSelected: (value) {
                        if (value == 'rename') _rename(playlist);
                        if (value == 'delete') _delete(playlist);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete playlist'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(BzRadius.modal),
                        child: artwork == null
                            ? Container(
                                width: 220,
                                height: 220,
                                color: theme.bzSurface1,
                                alignment: Alignment.center,
                                child: BzBnoteMark(
                                  size: 72,
                                  color: theme.bzText2,
                                ),
                              )
                            : Image.network(
                                artwork,
                                width: 220,
                                height: 220,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 220,
                                  height: 220,
                                  color: theme.bzSurface1,
                                  alignment: Alignment.center,
                                  child: BzBnoteMark(
                                    size: 72,
                                    color: theme.bzText2,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(playlist.name, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Playlist · ${playlist.tracks.length} songs · ${_remoteSynced ? 'Synced' : 'Pending sync / offline'}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.bzText2),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: playlist.tracks.isEmpty
                              ? null
                              : () => _playAll(playlist),
                          icon: BzSvgIcon(
                            name: 'play',
                            size: 17,
                            color: theme.bzBackground,
                          ),
                          label: const Text('Play'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: playlist.tracks.isEmpty
                              ? null
                              : () {
                                  final controller =
                                      ref.read(playerControllerProvider.notifier);
                                  controller.toggleShuffle();
                                  _playAll(playlist);
                                },
                          icon: BzSvgIcon(name: 'shuffle', size: 17),
                          label: const Text('Shuffle'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('SONGS',
                    style: TextStyle(
                      color: theme.bzText2,
                      fontSize: BzType.caption,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    )),
              ),
            ),
            if (playlist.tracks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'Add songs from Search using the track action menu.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.bzText2),
                    ),
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: playlist.tracks.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    if (!_ownerStillActive()) return;
                    final orderedTracks = List<FavoriteTrack>.from(playlist.tracks);
                    final moved = orderedTracks.removeAt(oldIndex);
                    orderedTracks.insert(newIndex, moved);
                    await _store.reorderTracks(
                      widget.ownerId, playlist.id, oldIndex, newIndex,
                    );
                    await _load(sync: false);
                    unawaited(_sync());
                    widget.onChanged?.call();
                  },
                  itemBuilder: (context, index) {
                    final track = playlist.tracks[index];
                    return Dismissible(
                      key: ValueKey(track.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: theme.bzError,
                        child: BzSvgIcon(
                          name: 'trash',
                          color: theme.bzBackground,
                        ),
                      ),
                      onDismissed: (_) async {
                        if (!_ownerStillActive()) return;
                        await _store.removeTrack(
                          widget.ownerId, playlist.id, track.id,
                        );
                        await _load(sync: false);
                        unawaited(_sync());
                        widget.onChanged?.call();
                      },
                      child: ListTile(
                        leading: track.artworkUrl == null
                            ? BzBnoteMark(size: 46, color: theme.bzText2)
                            : ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(BzRadius.artwork),
                                child: Image.network(
                                  track.artworkUrl!,
                                  width: 46,
                                  height: 46,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      BzBnoteMark(
                                          size: 46, color: theme.bzText2),
                                ),
                              ),
                        title: Text(track.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(track.artist,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: const BzSvgIcon(name: 'drag-handle'),
                        ),
                        onTap: () => _playTrack(playlist, index),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
