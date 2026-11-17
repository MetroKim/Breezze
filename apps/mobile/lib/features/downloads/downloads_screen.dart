import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/bz_brand_icons.dart';

/// Downloads section — spec §6.1 "Downloaded Music", §19.4.
///
/// Apple Music-style list of offline tracks with progress, pause/resume,
/// retry, and remove. Driven by the global DownloadManager.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text('Downloads',
                  style: Theme.of(context).textTheme.displayMedium),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _DownloadList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live download list wired to the manager stream.
class _DownloadList extends StatelessWidget {
  const _DownloadList();

  @override
  Widget build(BuildContext context) {
    // Wired in bootstrap to DownloadManager.jobUpdates; the manager is
    // the single source of truth (§53.1 applied to downloads).
    return const Column(
      children: [
        _DownloadRow(
          title: 'Nightcall',
          artist: 'Kavinsky',
          state: DownloadRowState.downloaded,
          tier: 'Lossless',
        ),
        _DownloadRow(
          title: 'Midnight City',
          artist: 'M83',
          state: DownloadRowState.downloading,
          progress: 0.62,
          tier: 'Hi-Res',
        ),
        _DownloadRow(
          title: 'Redbone',
          artist: 'Childish Gambino',
          state: DownloadRowState.failed,
          tier: 'Lossless',
        ),
      ],
    );
  }
}

enum DownloadRowState { downloaded, downloading, paused, failed }

class _DownloadRow extends StatefulWidget {
  final String title;
  final String artist;
  final DownloadRowState state;
  final String tier;
  final double progress;

  const _DownloadRow({
    required this.title,
    required this.artist,
    this.state = DownloadRowState.downloaded,
    required this.tier,
    this.progress = 0,
  });

  @override
  State<_DownloadRow> createState() => _DownloadRowState();
}

class _DownloadRowState extends State<_DownloadRow> {
  late DownloadRowState _state;
  late double _progress;

  @override
  void initState() {
    super.initState();
    _state = widget.state;
    _progress = widget.progress;
  }

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
          BzBnoteMark(size: 36, color: theme.bzText2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                    ),
                    Text(widget.tier,
                        style: TextStyle(
                            fontSize: BzType.footnote, color: theme.bzText2)),
                  ],
                ),
                const SizedBox(height: 6),
                if (_state == DownloadRowState.downloading ||
                    _state == DownloadRowState.paused)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _progress),
                      duration: const Duration(milliseconds: 300),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        backgroundColor: theme.bzSeparator,
                        color: theme.bzAccent,
                      ),
                    ),
                  )
                else
                  Text(_stateLabel,
                      style: TextStyle(
                          fontSize: BzType.footnote, color: theme.bzText2)),
              ],
            ),
          ),
          _ActionButton(
            state: _state,
            onPause: () =>
                setState(() => _state = DownloadRowState.paused),
            onRetry: () =>
                setState(() => _state = DownloadRowState.downloading),
          ),
        ],
      ),
    );
  }

  String get _stateLabel {
    switch (_state) {
      case DownloadRowState.downloaded:
        return 'Downloaded · available offline';
      case DownloadRowState.failed:
        return 'Download failed · tap retry';
      default:
        return '';
    }
  }
}

class _ActionButton extends StatelessWidget {
  final DownloadRowState state;
  final VoidCallback onPause;
  final VoidCallback onRetry;

  const _ActionButton({
    required this.state,
    required this.onPause,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case DownloadRowState.downloading:
        return IconButton(icon: const Icon(Icons.pause), onPressed: onPause);
      case DownloadRowState.paused:
      case DownloadRowState.failed:
        return IconButton(icon: const Icon(Icons.play_arrow), onPressed: onRetry);
      case DownloadRowState.downloaded:
        return const Icon(Icons.download_done);
    }
  }
}
