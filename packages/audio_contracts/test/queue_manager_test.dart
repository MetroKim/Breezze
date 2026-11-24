import 'package:breezze_audio_contracts/audio_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

QueueEntry entry(String id, {String origin = 'manual'}) => QueueEntry(
      entryId: id,
      trackId: 'track-$id',
      origin: origin,
      sourceContext: 'Test Album',
      insertedAtMs: DateTime.now().millisecondsSinceEpoch,
      trackVersion: 'v1',
    );

void main() {
  group('QueueManager (§53.4)', () {
    test('replaceWith sets current at startIndex', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      expect(q.current!.entryId, 'a');
      expect(q.upNext.map((e) => e.entryId), ['b', 'c']);
    });

    test('playNext inserts after current', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      q.playNext(entry('x'));
      expect(q.upNext.map((e) => e.entryId), ['x', 'b', 'c']);
    });

    test('source fallback keeps the selected slot and remaining tracks', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')], startIndex: 1);
      q.repeatMode = RepeatMode.repeatOne;
      q.shuffle = true;
      q.replaceCurrent(entry('preview'));
      expect(q.current!.entryId, 'preview');
      expect(q.upNext.map((item) => item.entryId), ['c']);
      expect(q.advance()!.entryId, 'preview');
    });

    test('playLast appends at end', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b')]);
      q.playLast(entry('z'));
      expect(q.upNext.map((e) => e.entryId), ['b', 'z']);
    });

    test('advance walks the queue; null at the end without repeat', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b')]);
      expect(q.advance()!.entryId, 'b');
      expect(q.advance(), isNull);
    });

    test('repeatOne returns the same entry', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b')]);
      q.repeatMode = RepeatMode.repeatOne;
      expect(q.advance()!.entryId, 'a'); // current item repeats immediately
      expect(q.advance()!.entryId, 'a'); // and remains the same
    });

    test('repeatAll wraps to the first entry', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b')]);
      q.repeatMode = RepeatMode.repeatAll;
      q.advance();
      expect(q.advance()!.entryId, 'a');
    });

    test('previous walks back; stays at first without repeat', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b')]);
      q.advance();
      expect(q.previous()!.entryId, 'a');
      expect(q.previous()!.entryId, 'a'); // stays
    });

    test('remove adjusts current index', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      q.remove('a');
      expect(q.current!.entryId, 'b');
    });

    test('reorder keeps stable entry IDs and current', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      q.reorder('c', 1); // a, c, b
      expect(q.upNext.map((e) => e.entryId), ['c', 'b']);
      expect(q.current!.entryId, 'a');
    });

    test('clear keeps current when asked', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      q.clear(keepCurrent: true);
      expect(q.current!.entryId, 'a');
      expect(q.upNext, isEmpty);
    });

 
    test('shuffle advances through every unplayed entry without falling back to sequential mode', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c'), entry('d')]);
      q.toggleShuffle();

      final visited = <String>{q.current!.entryId};
      for (var i = 0; i < 3; i++) {
        final next = q.advance();
        expect(next, isNotNull);
        visited.add(next!.entryId);
      }

      expect(visited, {'a', 'b', 'c', 'd'});
      expect(q.advance(), isNull);
    });

    test('shuffle repeat-all wraps to the first item in the shuffled cycle', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      q.toggleShuffle();
      final first = q.current!.entryId;
      q.repeatMode = RepeatMode.repeatAll;

      q.advance();
      q.advance();
      expect(q.advance()!.entryId, first);
    });

    test('shuffle toggle preserves unplayed entries set', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c'), entry('d')]);
      q.toggleShuffle();
      expect(q.upNext.length, 3);
      expect(q.upNext.map((e) => e.entryId).toSet(),
          {'b', 'c', 'd'});
      q.toggleShuffle();
      expect(q.upNext.map((e) => e.entryId), ['b', 'c', 'd']);
    });

    test('shuffle displayed Up Next is the actual playback sequence', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c'), entry('d')]);
      q.toggleShuffle();
      final displayed = q.upNext.map((e) => e.entryId).toList();
      final played = <String>[];
      for (var i = 0; i < displayed.length; i++) {
        played.add(q.advance()!.entryId);
      }
      expect(played, displayed);
      expect(q.upNext, isEmpty);
      expect(q.advance(), isNull);
    });

    test('Play Next has priority while shuffled without dropping remaining songs', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c'), entry('d')]);
      q.toggleShuffle();
      final old = q.upNext.map((e) => e.entryId).toList();
      q.playNext(entry('urgent'));
      expect(q.upNext.map((e) => e.entryId).toList(), ['urgent', ...old]);
      expect(q.advance()!.entryId, 'urgent');
      expect(q.upNext.map((e) => e.entryId).toList(), old);
    });

    test('Play Last stays at end of shuffled playback order', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      q.toggleShuffle();
      final old = q.upNext.map((e) => e.entryId).toList();
      q.playLast(entry('last'));
      expect(q.upNext.map((e) => e.entryId).toList(), [...old, 'last']);
    });

    test('Previous follows played shuffle sequence and not physical indexes', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c'), entry('d')]);
      q.toggleShuffle();
      final first = q.current!.entryId;
      final second = q.advance()!.entryId;
      expect(second, isNot(first));
      expect(q.previous()!.entryId, first);
      expect(q.advance()!.entryId, second);
    });

    test('queue-change listeners update when advancing shuffled order', () {
      var changed = 0;
      final q = QueueManager(onQueueChanged: () => changed++);
      q.replaceWith([entry('a'), entry('b')]);
      final before = changed;
      q.advance();
      expect(changed, before + 1);
    });

    test('restored shuffle keeps stable entry IDs, repeat and upcoming order', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      q.toggleShuffle();
      q.cycleRepeat();
      final savedOrder = q.shuffledOrder;
      final nextBefore = q.upNext.map((e) => e.entryId).toList();

      final fresh = QueueManager();
      fresh.restore(q.entries,
          currentEntryId: q.current!.entryId,
          repeat: q.repeatMode,
          shuffleEnabled: q.shuffle,
          shuffledOrder: savedOrder);
      expect(fresh.current!.entryId, 'a');
      expect(fresh.repeatMode, RepeatMode.repeatAll);
      expect(fresh.shuffle, isTrue);
      expect(fresh.upNext.map((e) => e.entryId).toList(), nextBefore);
      expect(fresh.advance()!.entryId, nextBefore.first);

      fresh.reset();
      expect(fresh.length, 0);
      expect(fresh.shuffle, isFalse);
      expect(fresh.repeatMode, RepeatMode.off);
    });

    test('restoration refuses invalid current or duplicate entry IDs', () {
      final q = QueueManager();
      expect(() => q.restore([entry('a')],
          currentEntryId: 'missing',
          repeat: RepeatMode.off,
          shuffleEnabled: false), throwsArgumentError);
      expect(() => q.restore([entry('a'), entry('a')],
          currentEntryId: 'a',
          repeat: RepeatMode.off,
          shuffleEnabled: false), throwsArgumentError);
    });

    test('Previous wraps in shuffled repeat-all mode', () {
      final q = QueueManager();
      q.replaceWith([entry('a'), entry('b'), entry('c')]);
      q.toggleShuffle();
      q.cycleRepeat();
      final last = q.shuffledOrder.last;
      expect(q.previous()!.entryId, last);
    });

    test('drag reorder changes real upcoming sequence without moving current', () {
      final queue = QueueManager();
      queue.replaceWith([entry('a'), entry('b'), entry('c'), entry('d')]);
      expect(queue.reorderUpNext('d', 0), isTrue);
      expect(queue.current!.entryId, 'a');
      expect(queue.upNext.map((e) => e.entryId), ['d', 'b', 'c']);
      expect(queue.advance()!.entryId, 'd');
      expect(queue.reorderUpNext('d', 1), isFalse);
    });

    test('shuffle drag reorder changes transport order and survives restore', () {
      final queue = QueueManager();
      queue.replaceWith([entry('a'), entry('b'), entry('c'), entry('d')]);
      queue.toggleShuffle();
      final last = queue.upNext.last.entryId;
      final originalMiddle = queue.upNext.take(2).map((e) => e.entryId).toList();
      expect(queue.reorderUpNext(last, 0), isTrue);
      expect(queue.upNext.map((e) => e.entryId).toList(),
          [last, ...originalMiddle]);
      final snapshot = queue.shuffledOrder;
      final restored = QueueManager();
      restored.restore(queue.entries,
        currentEntryId: queue.current!.entryId,
        repeat: queue.repeatMode,
        shuffleEnabled: true,
        shuffledOrder: snapshot,
      );
      expect(restored.upNext.map((e) => e.entryId).toList(),
          [last, ...originalMiddle]);
      expect(restored.advance()!.entryId, last);
    });
  });
}
