/// Breezze enhanced-LRC parser — port of the proven Chordline KMP LrcParser.
/// Word/line-synchronized lyrics (§10.1): line + word timestamps, sorted
/// timeline, binary-search lookup.
library;

/// One word (or syllable) in a synced lyric line.
class LyricWord {
  final String text;
  final Duration start;

  LyricWord(this.text, this.start);
}

/// One synced lyric line.
class LyricLine {
  final String text;
  final Duration start;
  final Duration end;
  final List<LyricWord> words;

  LyricLine({
    required this.text,
    required this.start,
    required this.end,
    this.words = const [],
  });
}

/// Parsed, timeline-sorted lyrics for one track.
class Lyrics {
  final String trackId;
  final List<LyricLine> lines;

  Lyrics(this.trackId, this.lines);

  /// Index of the line active at [position], or -1.
  int activeLineIndex(Duration position) {
    var lo = 0;
    var hi = lines.length - 1;
    var result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (lines[mid].start <= position) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  /// Word index active at [position] within [lineIndex], or -1.
  int activeWordIndex(int lineIndex, Duration position) {
    final words = (lineIndex >= 0 && lineIndex < lines.length)
        ? lines[lineIndex].words
        : const <LyricWord>[];
    var result = -1;
    for (var i = 0; i < words.length; i++) {
      if (words[i].start <= position) {
        result = i;
      } else {
        break;
      }
    }
    return result;
  }
}

/// Parses enhanced LRC: `[mm:ss.xx] line` plus inline `<mm:ss.xx>` word tags.
/// Lines are sorted by start; line end = next line start (LRC semantics).
class LrcParser {
  static final _lineRe = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _wordRe = RegExp(r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>');
  static const _defaultLine = Duration(seconds: 5);

  static Lyrics parse(String trackId, String raw) {
    final lines = <LyricLine>[];
    for (final rawLine in raw.split('\n')) {
      final line = _parseLine(rawLine);
      if (line != null) lines.add(line);
    }
    lines.sort((a, b) => a.start.compareTo(b.start));

    final withEnds = List<LyricLine>.generate(lines.length, (i) {
      final end = (i + 1 < lines.length)
          ? lines[i + 1].start
          : lines[i].start + _defaultLine;
      return LyricLine(
        text: lines[i].text,
        start: lines[i].start,
        end: end,
        words: lines[i].words,
      );
    });

    return Lyrics(trackId, withEnds);
  }

  static LyricLine? _parseLine(String raw) {
    final match = _lineRe.firstMatch(raw);
    if (match == null) return null;
    final start = _toDuration(match);
    final content = raw.replaceAll(_lineRe, '').trim();
    if (content.isEmpty) return null;

    // Each <tag> starts a word; text runs to the next tag.
    final tags = _wordRe.allMatches(content).toList();
    final words = <LyricWord>[];
    for (var i = 0; i < tags.length; i++) {
      final from = tags[i].end;
      final to = (i + 1 < tags.length) ? tags[i + 1].start : content.length;
      final word = content.substring(from, to).trim();
      if (word.isNotEmpty) words.add(LyricWord(word, _toDuration(tags[i])));
    }

    return LyricLine(
      text: content.replaceAll(_wordRe, '').trim(),
      start: start,
      end: start, // fixed in parse()
      words: words,
    );
  }

  static Duration _toDuration(MatchResultLike m) {
    final minutes = int.parse(m[1]!);
    final seconds = int.parse(m[2]!);
    final frac = m[3] ?? '0';
    var ms = 0;
    if (frac.length == 1) ms = int.parse(frac) * 100;
    if (frac.length == 2) ms = int.parse(frac) * 10;
    if (frac.length == 3) ms = int.parse(frac);
    return Duration(
        milliseconds: minutes * 60000 + seconds * 1000 + ms);
  }
}

typedef MatchResultLike = RegExpMatch;
