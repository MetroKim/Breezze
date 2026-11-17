class _FavoriteButton extends ConsumerWidget {
  final TrackInfo track;

  const _FavoriteButton({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.favorite_border),
      onPressed: () async {
        final added = await ref.read(favoritesStoreProvider).toggle(
              FavoriteTrack(
                id: track.id,
                title: track.title ?? '',
                artist: track.artist ?? '',
                artworkUrl: track.artworkUrl,
                durationMs: track.duration.inMilliseconds,
              ),
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(added ? 'Added to favorites' : 'Removed from favorites')));
        }
      },
    );
  }
}
