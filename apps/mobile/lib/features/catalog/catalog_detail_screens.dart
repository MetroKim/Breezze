import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../features/player/player_controller.dart';
import '../../widgets/bz_brand_icons.dart';

/// Artist page for a saved artist. The page is useful immediately for a
/// listener's saved tracks; catalog-only sections stay explicitly unavailable
/// until a canonical artist provider supplies verified metadata.
class ArtistDetailScreen extends ConsumerWidget {
  final String artist;
  final List<FavoriteTrack> savedTracks;
  final String? canonicalArtistId;
  final String? portraitUrl;

  const ArtistDetailScreen({
    super.key,
    required this.artist,
    required this.savedTracks,
    this.canonicalArtistId,
    this.portraitUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queue = [for (final track in savedTracks) track.toTrackInfo()];

    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: AppBar(
        title: const Text('Artist'),
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                Center(
                  child: ClipOval(
                    child: portraitUrl == null
                        ? Container(
                            width: 156,
                            height: 156,
                            color: theme.bzSurface1,
                            alignment: Alignment.center,
                            child: BzSvgIcon(
                              name: 'mic',
                              size: 54,
                              color: theme.bzText2,
                            ),
                          )
                        : Image.network(
                            portraitUrl!,
                            width: 156,
                            height: 156,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 156,
                              height: 156,
                              color: theme.bzSurface1,
                              alignment: Alignment.center,
                              child: BzSvgIcon(
                                name: 'mic',
                                size: 54,
                                color: theme.bzText2,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(artist,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  canonicalArtistId == null
                      ? 'Artist from your saved music'
                      : 'Verified artist profile',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.bzText2,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: savedTracks.isEmpty
                          ? null
                           : () => ref.read(playerControllerProvider.notifier).playTrack(
                                trackId: savedTracks.first.id,
                                queue: queue,
                                origin: 'library',
                                sourceContext: artist,
                              ),
                      icon: BzSvgIcon(
                        name: 'play',
                        color: theme.bzBackground,
                        size: 18,
                      ),
                      label: const Text('Play saved songs'),
                    ),
                    OutlinedButton.icon(
                      onPressed: null,
                      icon: const BzSvgIcon(name: 'user-round-plus'),
                      label: const Text('Follow'),
                    ),
                  ],
                ),
                if (canonicalArtistId == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Follow and artist-wide catalog actions become available when a verified artist profile is connected.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.bzText2,
                      ),
                    ),
                  ),
                const SizedBox(height: 28),
                _CatalogSection(
                  title: 'Saved Songs',
                  subtitle: 'Songs by this artist that you have saved.',
                  available: savedTracks.isNotEmpty,
                  child: Column(
                    children: [
                      for (var i = 0; i < savedTracks.length; i++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _TrackArtwork(
                            url: savedTracks[i].artworkUrl,
                            size: 48,
                          ),
                          title: Text(
                            savedTracks[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            savedTracks[i].artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => ref.read(playerControllerProvider.notifier).playTrack(
                            trackId: savedTracks[i].id,
                            queue: queue,
                            startIndex: i,
                            origin: 'library',
                            sourceContext: artist,
                          ),
                        ),
                    ],
                  ),
                ),
                for (final section in const [
                  'Essential Albums',
                  'Essential Songs',
                  'Music Videos',
                  'Upcoming Concerts',
                  'Similar Artists',
                  'Discography',
                  'Singles & EPs',
                ])
                  _CatalogSection(
                    title: section,
                    subtitle: 'Verified artist catalog data is required for this section.',
                    available: false,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final queue = tracks;

    Future<void> play({bool shuffle = false}) async {
      if (queue.isEmpty) return;
      final player = ref.read(playerControllerProvider.notifier);
      await player.playTrack(
        trackId: queue.first.id,
        queue: queue,
        origin: 'album',
        sourceContext: canonicalAlbumId,
      );
      if (shuffle) player.toggleShuffle();
    }

    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: AppBar(
        title: const Text('Album'),
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
                          onTap: () => ref.read(playerControllerProvider.notifier).playTrack(
                            trackId: tracks[i].id,
                            queue: queue,
                            startIndex: i,
                            origin: 'album',
                            sourceContext: canonicalAlbumId,
                          ),
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
