import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../widgets/bz_brand_icons.dart';
import '../player/player_controller.dart';

/// Search screen — real results from the live source (§04).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<BzTrack> _results = [];
  var _loading = false;
  var _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    final op = await ref.read(youtubeSourceProvider).search(query.trim());
    setState(() {
      _loading = false;
      _results = op is ProviderOk<List<ProviderTrack>>
          ? op.value
              .map((t) => BzTrack(
                    id: t.breezzeTrackId,
                    title: t.title,
                    artist: t.artist,
                    artworkUrl: t.artworkUrl,
                    duration: t.duration,
                  ))
              .toList()
          : [];
    });
  }

  Future<void> _download(BzTrack track) async {
    final dir = await downloadsDirectory();
    await DownloadsLibrary(
      root: dir,
      source: ref.read(youtubeSourceProvider),
      lyrics: LyricsProvider(HttpLyrics()),
    ).download(track);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded: ${track.title}')));
    }
  }

  void _play(BzTrack track) {
    ref
        .read(playerControllerProvider.notifier)
        .playTrack(trackId: track.id, origin: 'search');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: TextField(
              controller: _controller,
              onSubmitted: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search songs, artists…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.bzSurface1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(BzRadius.input),
                  borderSide: BorderSide(color: theme.bzSeparator),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? Center(
                        child: BzBnoteMark(size: 64, color: theme.bzText2),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Text('No results',
                                style: theme.textTheme.titleMedium),
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(0, 8, 0, 220),
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final track = _results[i];
                              return ListTile(
                                leading: track.artworkUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            BzRadius.artwork),
                                        child: Image.network(
                                          track.artworkUrl!,
                                          width: 48,
                                          height: 48,
                                          errorBuilder: (_, __, ___) =>
                                              BzBnoteMark(
                                                  size: 48,
                                                  color: theme.bzText2),
                                        ),
                                      )
                                    : BzBnoteMark(
                                        size: 48, color: theme.bzText2),
                                title: Text(track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                trailing: IconButton(
                                  icon: const Icon(Icons.download_outlined),
                                  onPressed: () => _download(track),
                                ),
                                onTap: () => _play(track),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

/// App-private downloads directory (per platform, bootstrap-provided).
Future<Directory> downloadsDirectory() async {
  final base = Directory.systemTemp;
  final dir = Directory('${base.path}/breezze_downloads');
  await dir.create(recursive: true);
  return dir;
}
