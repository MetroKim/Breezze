import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_design_system/breezze_design_system.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../app/downloads_controller.dart';
import '../../features/player/player_controller.dart';
import '../../widgets/bz_brand_icons.dart';

/// Browse uses live source search for genre discovery. It does not label
/// provider search results as official charts or editorial recommendations.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  static const _genres = [
    'Afrobeats',
    'Bongo Flava',
    'Amapiano',
    'Gospel',
    'Hip-Hop',
    'R&B',
    'Jazz',
    'Electronic',
  ];

  String _selectedGenre = _genres.first;
  List<BzTrack> _tracks = [];
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadGenre(_selectedGenre);
    });
  }

  Future<void> _loadGenre(String genre) async {
    final requestId = ++_requestId;
    setState(() {
      _selectedGenre = genre;
      _loading = true;
      _error = null;
      _tracks = [];
    });

    try {
      final result = await ref.read(youtubeSourceProvider).search('$genre music');
      if (!mounted || requestId != _requestId) return;

      if (result is ProviderOk<List<ProviderTrack>>) {
        setState(() {
          _tracks = result.value
              .map((track) => BzTrack(
                    id: track.breezzeTrackId,
                    title: track.title,
                    artist: track.artist,
                    artworkUrl: track.artworkUrl,
                    duration: track.duration,
                  ))
              .toList();
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'This music source could not return results right now.';
        });
      }
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = 'Could not connect to the music source. Try again.';
      });
    }
  }

  void _openCollection(_BrowseDestination destination) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BrowseCollectionScreen(destination: destination),
      ),
    );
  }

  void _play(int index) {
    if (_tracks.isEmpty) return;
    final queue = [
      for (final track in _tracks)
        TrackInfo(
          id: track.id,
          title: track.title,
          artist: track.artist,
          artworkUrl: track.artworkUrl,
          duration: track.duration,
        ),
    ];
    ref.read(playerControllerProvider.notifier).playTrack(
          trackId: _tracks[index].id,
          queue: queue,
          startIndex: index,
          origin: 'browse',
          sourceContext: _selectedGenre,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = ref.watch(downloadProgressProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Browse', style: theme.textTheme.displayMedium),
                const SizedBox(height: 6),
                Text('Explore music by genre.',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 18),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _genres.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final genre = _genres[index];
                      final selected = genre == _selectedGenre;
                      return ChoiceChip(
                        label: Text(genre),
                        selected: selected,
                        onSelected: (_) => _loadGenre(genre),
                        selectedColor: theme.bzText1,
                        backgroundColor: theme.bzSurface1,
                        labelStyle: TextStyle(
                          color: selected ? theme.bzBackground : theme.bzText1,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide(color: theme.bzSeparator),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text('Discover', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1080
                        ? 4
                        : constraints.maxWidth >= 620
                            ? 3
                            : 2;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _browseDestinations.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.45,
                      ),
                      itemBuilder: (context, index) {
                        final destination = _browseDestinations[index];
                        return Material(
                          color: theme.bzSurface1,
                          borderRadius: BorderRadius.circular(BzRadius.card),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(BzRadius.card),
                            onTap: () => _openCollection(destination),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(BzRadius.card),
                                border: Border.all(color: theme.bzSeparator),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: theme.bzSurface2,
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    alignment: Alignment.center,
                                    child: BzSvgIcon(
                                      name: destination.icon,
                                      size: 19,
                                      color: theme.bzAccent,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          destination.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelLarge,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          destination.description,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.bzText2,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: 7,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (_, __) => const BzSkeletonTrackRow(),
                  )
                : _error != null
                    ? _MessageState(
                        icon: 'wifi-off',
                        title: 'Music is unavailable',
                        message: _error!,
                        onRetry: () => _loadGenre(_selectedGenre),
                      )
                    : _tracks.isEmpty
                        ? _MessageState(
                            icon: 'music-note',
                            title: 'No tracks found',
                            message: 'Try another genre or search for an artist.',
                            onRetry: () => _loadGenre(_selectedGenre),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.fromLTRB(0, 8, 0, BzBreakpoints.bottomClearance(context, compact: 220)),
                            itemCount: _tracks.length,
                            itemBuilder: (context, index) {
                              final track = _tracks[index];
                              final download = progress[track.id];
                              return ListTile(
                                leading: track.artworkUrl == null
                                    ? BzBnoteMark(
                                        size: 48, color: theme.bzText2)
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            BzRadius.artwork),
                                        child: Image.network(
                                          track.artworkUrl!,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              BzBnoteMark(
                                            size: 48,
                                            color: theme.bzText2,
                                          ),
                                        ),
                                      ),
                                title: Text(track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                trailing: download != null
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : IconButton(
                                        tooltip: 'Download',
                                        icon: BzSvgIcon(name: 'download', size: 20),
                                        onPressed: () => ref
                                            .read(downloadProgressProvider
                                                .notifier)
                                            .download(track),
                                      ),
                                onTap: () => _play(index),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final String icon;
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BzSvgIcon(name: icon, size: 36, color: theme.bzText2),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}


class _BrowseDestination {
  final String title;
  final String description;
  final String icon;

  const _BrowseDestination(this.title, this.description, this.icon);
}

const _browseDestinations = <_BrowseDestination>[
  _BrowseDestination('Latest Songs', 'Recently added tracks from verified catalog sources.', 'music-note'),
  _BrowseDestination('New Releases', 'New albums and singles with confirmed release dates.', 'disc-3'),
  _BrowseDestination('Trending Songs', 'Tracks trending in a defined region and time window.', 'refresh'),
  _BrowseDestination('Daily Top 100', 'A verified daily chart with an explicit territory.', 'star'),
  _BrowseDestination('Coming Soon', 'Upcoming releases with confirmed release metadata.', 'calendar'),
  _BrowseDestination('Music Videos', 'Official music videos from authorized video sources.', 'video'),
  _BrowseDestination('Charts', 'Global, regional and genre charts with source attribution.', 'grid'),
  _BrowseDestination('Browse by Genre', 'Explore catalog music by genre and subgenre.', 'compass'),
  _BrowseDestination('Moods & Activities', 'Curated listening collections for moods and activities.', 'favorite'),
  _BrowseDestination('City Charts', 'City-level charts backed by verified regional data.', 'globe'),
  _BrowseDestination('Upcoming Concerts', 'Artist events with confirmed venue and ticket details.', 'calendar'),
  _BrowseDestination('Seasonal Collections', 'Time-limited music collections and seasonal features.', 'disc-3'),
  _BrowseDestination('Artist Spotlight', 'Editorial artist features backed by catalog metadata.', 'user-round'),
];

class _BrowseCollectionScreen extends ConsumerStatefulWidget {
  final _BrowseDestination destination;
  const _BrowseCollectionScreen({required this.destination});

  @override
  ConsumerState<_BrowseCollectionScreen> createState() => _BrowseCollectionScreenState();
}

class _BrowseCollectionScreenState extends ConsumerState<_BrowseCollectionScreen> {
  static const _genres = ['Afrobeats','Bongo Flava','Amapiano','Gospel','Hip-Hop','R&B','Jazz','Electronic','Pop','Rock','Soul','Dancehall'];
  static const _moods = ['Focus','Workout','Chill','Party','Sleep','Commute','Feel good','Romance','Meditation','Running','Study','Driving'];
  String _selected = '';
  List<BzTrack> _tracks = [];
  bool _loading = false;
  String? _error;
  int _generation = 0;

  bool get _genre => widget.destination.title == 'Browse by Genre';
  bool get _mood => widget.destination.title == 'Moods & Activities';
  bool get _searchable => _genre || _mood;
  List<String> get _choices => _genre ? _genres : _moods;

  @override
  void initState() {
    super.initState();
    if (_searchable) {
      _selected = _choices.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search(_selected);
      });
    }
  }

  Future<void> _search(String choice) async {
    final generation = ++_generation;
    setState(() {
      _selected = choice;
      _loading = true;
      _error = null;
      _tracks = [];
    });
    try {
      final result = await ref.read(youtubeSourceProvider).search('$choice music');
      if (!mounted || generation != _generation) return;
      if (result is ProviderOk<List<ProviderTrack>>) {
        setState(() {
          _tracks = result.value.map((track) => BzTrack(
            id: track.breezzeTrackId,
            title: track.title,
            artist: track.artist,
            artworkUrl: track.artworkUrl,
            duration: track.duration,
          )).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'The connected music source could not return search results.';
        });
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Could not reach the music source. Check your connection and retry.';
      });
    }
  }

  void _play(int index) {
    if (_tracks.isEmpty) return;
    final queue = [for (final track in _tracks) TrackInfo(
      id: track.id, title: track.title, artist: track.artist,
      artworkUrl: track.artworkUrl, duration: track.duration,
    )];
    ref.read(playerControllerProvider.notifier).playTrack(
      trackId: _tracks[index].id,
      queue: queue,
      startIndex: index,
      origin: 'browse',
      sourceContext: widget.destination.title + ': ' + _selected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = ref.watch(downloadProgressProvider);
    return Scaffold(
      backgroundColor: theme.bzBackground,
      appBar: AppBar(
        title: Text(widget.destination.title),
        leading: IconButton(
          tooltip: 'Back to Browse',
          icon: const BzSvgIcon(name: 'chevron-left'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: _searchable
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.destination.description, style: theme.textTheme.bodyMedium),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [for (final choice in _choices)
                                ChoiceChip(
                                  label: Text(choice),
                                  selected: _selected == choice,
                                  onSelected: (_) => _search(choice),
                                )],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.bzSurface1,
                                borderRadius: BorderRadius.circular(BzRadius.card),
                                border: Border.all(color: theme.bzSeparator),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BzSvgIcon(name: 'info', size: 18, color: theme.bzText2),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(
                                    'These are track-search matches from the connected source. They are not verified editorial playlists, mood classifications or official genre charts.',
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2),
                                  )),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(_genre ? 'Genre search matches' : 'Mood search matches', style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _loading
                            ? ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: 6,
                                separatorBuilder: (_, __) => const SizedBox(height: 14),
                                itemBuilder: (_, __) => const BzSkeletonTrackRow(),
                              )
                            : _error != null
                                ? _BrowseMessageState(
                                    icon: 'wifi-off', title: 'Music source unavailable',
                                    message: _error!, onRetry: () => _search(_selected),
                                  )
                                : _tracks.isEmpty
                                    ? _BrowseMessageState(
                                        icon: 'music-note', title: 'No matches found',
                                        message: 'Try another selection or retry this search.',
                                        onRetry: () => _search(_selected),
                                      )
                                    : ListView.builder(
                                        padding: EdgeInsets.fromLTRB(0, 8, 0, BzBreakpoints.bottomClearance(context, compact: 220)),
                                        itemCount: _tracks.length,
                                        itemBuilder: (context, index) {
                                          final track = _tracks[index];
                                          final download = progress[track.id];
                                          return ListTile(
                                            leading: track.artworkUrl == null
                                                ? BzBnoteMark(size: 48, color: theme.bzText2)
                                                : ClipRRect(
                                                    borderRadius: BorderRadius.circular(BzRadius.artwork),
                                                    child: Image.network(
                                                      track.artworkUrl!, width: 48, height: 48, fit: BoxFit.cover,
                                                      errorBuilder: (_, __, ___) => BzBnoteMark(size: 48, color: theme.bzText2),
                                                    ),
                                                  ),
                                            title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                            subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                                            trailing: download != null
                                                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                                : IconButton(
                                                    tooltip: 'Download',
                                                    icon: const BzSvgIcon(name: 'download', size: 20),
                                                    onPressed: () => ref.read(downloadProgressProvider.notifier).download(track),
                                                  ),
                                            onTap: () => _play(index),
                                          );
                                        },
                                      ),
                      ),
                    ],
                  )
                : _unavailable(theme),
          ),
        ),
      ),
    );
  }

  Widget _unavailable(ThemeData theme) {
    final destination = widget.destination;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: theme.bzSurface1,
            borderRadius: BorderRadius.circular(BzRadius.card),
            border: Border.all(color: theme.bzSeparator),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54, height: 54,
                decoration: BoxDecoration(color: theme.bzSurface2, borderRadius: BorderRadius.circular(15)),
                alignment: Alignment.center,
                child: BzSvgIcon(name: destination.icon, size: 27, color: theme.bzAccent),
              ),
              const SizedBox(height: 18),
              Text(destination.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(destination.description, style: theme.textTheme.bodyMedium?.copyWith(color: theme.bzText2)),
              const SizedBox(height: 22),
              Row(children: [
                BzSvgIcon(name: 'info', size: 19, color: theme.bzAccent),
                const SizedBox(width: 9),
                Text('Not available yet', style: theme.textTheme.titleMedium),
              ]),
              const SizedBox(height: 10),
              Text(
                'A verified catalog or editorial provider is required for this section. Breezze will not substitute generic search results or invented rankings.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(destination.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.bzText2)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('What belongs in this section', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final item in destination.previewSections)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              BzSvgIcon(name: 'check', size: 17, color: theme.bzText2),
              const SizedBox(width: 10),
              Expanded(child: Text(item, style: theme.textTheme.bodyMedium)),
            ]),
          ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Back to Browse'),
        ),
      ],
    );
  }
}
