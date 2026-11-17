import 'dart:io';

import 'package:breezze_api_client/breezze_api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bootstrap.dart';
import '../../widgets/bz_brand_icons.dart';
import '../search/search_screen.dart' show downloadsDirectory;

/// Downloads library — real offline tracks with cover art (§6.1).
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  List<DownloadedTrack> _tracks = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final dir = await downloadsDirectory();
    final library = DownloadsLibrary(
      root: dir,
      source: ref.read(youtubeSourceProvider),
      lyrics: ref.read(lyricsProvider),
    );
    final tracks = await library.list();
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Downloads',
                      style: theme.textTheme.displayMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tracks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            BzBnoteMark(size: 64, color: theme.bzText2),
                            const SizedBox(height: 16),
                            Text('No downloads yet',
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(
                                'Search a song and tap the download icon.',
                                style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 220),
                        itemCount: _tracks.length,
                        itemBuilder: (context, i) {
                          final track = _tracks[i];
                          return _DownloadRow(track: track);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final DownloadedTrack track;

  const _DownloadRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.bzSurface1,
        borderRadius: BorderRadius.circular(BzRadius.card),
        border: Border.all(color: theme.bzSeparator),
      ),
      child: Row(
        children: [
          track.coverPath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(BzRadius.artwork),
                  child: Image.file(
                    File(track.coverPath!),
                    width: 48,
                    height: 48,
                    errorBuilder: (_, __, ___) =>
                        BzBnoteMark(size: 48, color: theme.bzText2),
                  ),
                )
              : BzBnoteMark(size: 48, color: theme.bzText2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                Text(
                    '${track.artist}${track.lyricsPath != null ? ' · lyrics saved' : ''}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.download_done, color: Colors.green),
        ],
      ),
    );
  }
}
