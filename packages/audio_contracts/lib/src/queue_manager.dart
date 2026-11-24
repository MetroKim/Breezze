/// Breezze queue manager — spec §53.4.
///
/// Ports the proven Chordline KMP GaplessQueue semantics to Dart and
/// extends them with the spec's queue rules: stable entry IDs, Play Next
/// vs Play Last, order-preserving shuffle, distinct repeat-one/repeat-all,
/// and queue restoration.
library;

import 'dart:math' as math;

import 'audio_engine_adapter.dart';

/// Repeat modes are distinct states (§53.4).
enum RepeatMode { off, repeatAll, repeatOne }

/// Shuffle must avoid duplicate insertion and preserve the unplayed queue
/// when toggled (§53.4).
class QueueManager {
  final List<QueueEntry> _entries = [];
  final List<QueueEntry> _history = [];

  /// Index of the current entry; null when nothing plays.
  int? _currentIndex;

  RepeatMode repeatMode = RepeatMode.off;
  bool shuffle = false;

  /// Shuffled order of unplayed entries while shuffle is on (§53.4).
  List<String> _shuffledOrder = [];

  /// Callback when the queue mutates; drives the Queue sheet UI.
  final void Function()? onQueueChanged;

  QueueManager({this.onQueueChanged});

  /// Current entry, or null when idle.
  QueueEntry? get current =>
      (_currentIndex != null && _currentIndex! < _entries.length)
          ? _entries[_currentIndex!]
          : null;

  /// The UI and OS media queue must display the same order advance() uses.
  /// In shuffle mode physical list indexes are not playback ordering.
  List<QueueEntry> get upNext {
    final index = _currentIndex;
    if (!shuffle || index == null) {
      return List.unmodifiable(index == null ? _entries : _entries.sublist(index + 1));
    }
    final position = _shuffledOrder.indexOf(_entries[index].entryId);
    if (position < 0) return const <QueueEntry>[];
    final byId = {for (final item in _entries) item.entryId: item};
    return List.unmodifiable(_shuffledOrder.skip(position + 1)
        .map((id) => byId[id]).whereType<QueueEntry>());
  }

  List<QueueEntry> get history => List.unmodifiable(_history);

  String? get playingFromLabel => current?.sourceContext;

  int get length => _entries.length;

  /// Read-only stable order for serialization; stream URLs are never stored.
  List<QueueEntry> get entries => List.unmodifiable(_entries);
  List<String> get shuffledOrder => List.unmodifiable(_shuffledOrder);

  /// Restores the same queue without starting an unauthorized media source.
  void restore(
    List<QueueEntry> entries, {
    required String currentEntryId,
    required RepeatMode repeat,
    required bool shuffleEnabled,
    List<String> shuffledOrder = const [],
  }) {
    final ids = entries.map((e) => e.entryId).toSet();
    final index = entries.indexWhere((e) => e.entryId == currentEntryId);
    if (entries.isEmpty || ids.length != entries.length || index < 0) {
      throw ArgumentError('INVALID_QUEUE_SNAPSHOT');
    }
    _entries
      ..clear()
      ..addAll(entries);
    _history.clear();
    _currentIndex = index;
    repeatMode = repeat;
    shuffle = shuffleEnabled;
    if (shuffle &&
        shuffledOrder.length == entries.length &&
        shuffledOrder.toSet().length == ids.length &&
        shuffledOrder.toSet().containsAll(ids)) {
      _shuffledOrder = List.of(shuffledOrder);
    } else {
      _shuffledOrder = [];
      _rebuildShuffle();
    }
    onQueueChanged?.call();
  }

  /// Explicit Stop and account switches must not leak prior queue modes.
  void reset() {
    _entries.clear();
    _history.clear();
    _currentIndex = null;
    repeatMode = RepeatMode.off;
    shuffle = false;
    _shuffledOrder = [];
    onQueueChanged?.call();
  }

  // ------------------------------------------------------------------
  // Mutations
  // ------------------------------------------------------------------

  /// Replaces the queue and starts at [startIndex].
  void replaceWith(List<QueueEntry> entries, {int startIndex = 0}) {
    if (entries.isEmpty) return;
    if (current != null) _history.add(current!);
    _entries
      ..clear()
      ..addAll(entries);
    _currentIndex = math.min(startIndex, entries.length - 1);
    _rebuildShuffle();
    onQueueChanged?.call();
  }

  /// Appends to the end (Play Last, §53.4).
  void playLast(QueueEntry entry) {
    _entries.add(entry);
    _currentIndex ??= 0;
    if (shuffle && _shuffledOrder.isNotEmpty) {
      _shuffledOrder.add(entry.entryId);
    } else {
      _rebuildShuffle();
    }
    onQueueChanged?.call();
  }

  /// Inserts immediately after the current item (Play Next, §53.4).
  void playNext(QueueEntry entry) {
    final insertAt = (_currentIndex ?? -1) + 1;
    final previousCurrentId = current?.entryId;
    _entries.insert(insertAt, entry);
    if (_currentIndex == null) _currentIndex = 0;
    if (shuffle && previousCurrentId != null) {
      final pos = _shuffledOrder.indexOf(previousCurrentId);
      if (pos < 0) {
        _rebuildShuffle();
      } else {
        // Play Next is explicitly ordered, even while shuffle is enabled.
        _shuffledOrder.insert(pos + 1, entry.entryId);
      }
    } else {
      _rebuildShuffle();
    }
    onQueueChanged?.call();
  }

  /// Switch the current recording's source while preserving the upcoming queue.
  void replaceCurrent(QueueEntry entry) {
    final index = _currentIndex;
    if (index == null) return;
    final oldId = _entries[index].entryId;
    _entries[index] = entry;
    if (shuffle) {
      final pos = _shuffledOrder.indexOf(oldId);
      if (pos < 0) {
        _rebuildShuffle();
      } else {
        _shuffledOrder[pos] = entry.entryId;
      }
    }
    onQueueChanged?.call();
  }

  /// Removes by entryId; returns false when not found.
  bool remove(String entryId) {
    final idx = _entries.indexWhere((e) => e.entryId == entryId);
    if (idx < 0) return false;
    _entries.removeAt(idx);
    if (_currentIndex != null) {
      if (idx < _currentIndex!) {
        _currentIndex = _currentIndex! - 1;
      } else if (idx == _currentIndex!) {
        _currentIndex =
            _entries.isEmpty ? null : math.min(idx, _entries.length - 1);
      }
    }
    if (shuffle) _shuffledOrder.remove(entryId);
    if (!shuffle || _shuffledOrder.isEmpty) _rebuildShuffle();
    onQueueChanged?.call();
    return true;
  }

  /// Reorder preserves stable entry IDs (§53.4).
  bool reorder(String entryId, int newPosition) {
    final from = _entries.indexWhere((e) => e.entryId == entryId);
    if (from < 0) return false;
    final currentId = current?.entryId;
    final entry = _entries.removeAt(from);
    final to = math.max(0, math.min(newPosition, _entries.length));
    _entries.insert(to, entry);
    _currentIndex = _entries.indexWhere((e) => e.entryId == currentId);
    if (_currentIndex != null && _currentIndex! < 0) _currentIndex = null;
    _rebuildShuffle();
    onQueueChanged?.call();
    return true;
  }

  void clear({bool keepCurrent = true}) {
    if (keepCurrent && current != null) {
      final keep = current!;
      _entries
        ..clear()
        ..add(keep);
      _currentIndex = 0;
    } else {
      _entries.clear();
      _currentIndex = null;
    }
    _rebuildShuffle();
    onQueueChanged?.call();
  }

  // ------------------------------------------------------------------
  // Traversal
  // ------------------------------------------------------------------

  /// Advances according to repeat + shuffle; null when the queue is done.
  QueueEntry? advance() {
    if (_entries.isEmpty) return null;
    final cur = _currentIndex;

    if (repeatMode == RepeatMode.repeatOne && cur != null) {
      return _entries[cur]; // same entry again
    }

    final next = _nextIndex(cur);
    if (next == null) return null; // queue finished
    _currentIndex = next;
    onQueueChanged?.call();
    return _entries[next];
  }

  QueueEntry? previous() {
    if (_entries.isEmpty || _currentIndex == null) return null;
    if (shuffle) {
      final pos = _shuffledOrder.indexOf(current!.entryId);
      if (pos > 0) {
        final prev = _entries.indexWhere((e) => e.entryId == _shuffledOrder[pos - 1]);
        if (prev >= 0) {
          _currentIndex = prev;
          onQueueChanged?.call();
          return _entries[prev];
        }
      }
      return current;
    }
    if (_currentIndex! > 0) {
      _currentIndex = _currentIndex! - 1;
      onQueueChanged?.call();
      return _entries[_currentIndex!];
    }
    if (repeatMode == RepeatMode.repeatAll) {
      _currentIndex = _entries.length - 1;
      onQueueChanged?.call();
      return _entries.last;
    }
    return _entries.first; // stay at first
  }

  int? _nextIndex(int? cur) {
    if (cur == null) return _entries.isEmpty ? null : 0;
    if (shuffle) {
      final order = _shuffledOrder;
      final pos = order.indexOf(_entries[cur].entryId);
      // A missing current entry indicates a stale shuffle snapshot. Do not
      // silently fall back to sequential playback and violate shuffle mode.
      if (pos < 0) return null;
      if (pos + 1 < order.length) {
        final nextIndex =
            _entries.indexWhere((e) => e.entryId == order[pos + 1]);
        return nextIndex < 0 ? null : nextIndex;
      }
      if (repeatMode == RepeatMode.repeatAll && order.isNotEmpty) {
        final firstIndex =
            _entries.indexWhere((e) => e.entryId == order.first);
        return firstIndex < 0 ? null : firstIndex;
      }
      return null;
    }
    if (cur + 1 < _entries.length) return cur + 1;
    if (repeatMode == RepeatMode.repeatAll) return 0;
    return null;
  }

  void _rebuildShuffle() {
    if (!shuffle) return;

    // Keep the current entry in the snapshot so advance() can find its
    // position. Shuffle only entries that have not played yet.
    final ordered = <QueueEntry>[];
    if (_currentIndex != null && _currentIndex! < _entries.length) {
      ordered.add(_entries[_currentIndex!]);
      if (_currentIndex! + 1 < _entries.length) {
        final remaining = _entries.sublist(_currentIndex! + 1);
        remaining.shuffle(math.Random());
        ordered.addAll(remaining);
      }
    } else {
      ordered.addAll(_entries);
      ordered.shuffle(math.Random());
    }
    _shuffledOrder = ordered.map((e) => e.entryId).toList();
  }

  /// Toggling shuffle preserves the unplayed queue (§53.4).
  void toggleShuffle() {
    shuffle = !shuffle;
    if (shuffle) {
      _rebuildShuffle();
    } else {
      _shuffledOrder = [];
    }
    onQueueChanged?.call();
  }

  void cycleRepeat() {
    switch (repeatMode) {
      case RepeatMode.off:
        repeatMode = RepeatMode.repeatAll;
      case RepeatMode.repeatAll:
        repeatMode = RepeatMode.repeatOne;
      case RepeatMode.repeatOne:
        repeatMode = RepeatMode.off;
    }
    onQueueChanged?.call();
  }
}
