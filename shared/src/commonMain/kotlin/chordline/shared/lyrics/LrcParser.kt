/*
 * Chordline — lyrics entities and enhanced-LRC parser.
 *
 * Word/syllable-synced lyrics are a flagship feature in both parents:
 * BitChord aggregates 13 providers; Liner animates syllable-synced lines.
 * The shared pipeline parses enhanced LRC (line + word timestamps) once
 * and exposes it to every surface.
 */
package chordline.shared.lyrics

/** One word (or syllable) inside a synced lyric line. */
data class LyricWord(
    val text: String,
    /** Start time in ms. */
    val startMs: Long,
    /** End time in ms; null when unknown (falls back to line end). */
    val endMs: Long? = null,
)

/** One synced lyric line. */
data class LyricLine(
    val text: String,
    val startMs: Long,
    val endMs: Long,
    /** Word-level sync data when the provider supplies it. */
    val words: List<LyricWord> = emptyList(),
)

/** Fully parsed, timeline-sorted lyrics for a track. */
data class Lyrics(
    val trackId: String,
    val lines: List<LyricLine>,
) {
    /** Index of the line active at [positionMs], or -1. */
    fun activeLineIndex(positionMs: Long): Int {
        var lo = 0
        var hi = lines.lastIndex
        var result = -1
        while (lo <= hi) {
            val mid = (lo + hi) / 2
            val line = lines[mid]
            if (line.startMs <= positionMs) {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    /** Word index active at [positionMs] within the given line, or -1. */
    fun activeWordIndex(lineIndex: Int, positionMs: Long): Int {
        val words = lines.getOrNull(lineIndex)?.words ?: return -1
        var result = -1
        for ((i, w) in words.withIndex()) {
            if (w.startMs <= positionMs) result = i else break
        }
        return result
    }
}

/**
 * Parses enhanced LRC: standard `[mm:ss.xx] line` plus word tags
 * `<mm:ss.xx>` inline. Lines are sorted by start time; end times are the
 * next line's start (standard LRC semantics).
 */
object LrcParser {

    private val lineRegex = Regex("""\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?]""")
    private val wordRegex = Regex("""<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>""")

    fun parse(trackId: String, raw: String): Lyrics {
        val lines = raw.lineSequence()
            .mapNotNull { rawLine -> parseLine(rawLine) }
            .sortedBy { it.startMs }

        val withEnds = lines.mapIndexed { i, line ->
            val end = lines.getOrNull(i + 1)?.startMs ?: (line.startMs + DEFAULT_LINE_MS)
            line.copy(endMs = end)
        }
        return Lyrics(trackId, withEnds)
    }

    private fun parseLine(raw: String): LyricLine? {
        val timestamp = lineRegex.find(raw) ?: return null
        val startMs = toMs(timestamp)
        val content = raw.replace(lineRegex, "").trim()
        if (content.isEmpty()) return null

        // Each <tag> starts a word: the text runs until the next tag.
        val tags = wordRegex.findAll(content).toList()
        val wordSegments = tags.mapIndexed { i, m ->
            val from = m.range.last + 1
            val to = tags.getOrNull(i + 1)?.range?.first ?: content.length
            LyricWord(content.substring(from, to).trim(), toMs(m))
        }.filter { it.text.isNotEmpty() }

        return LyricLine(
            text = content.replace(wordRegex, "").trim(),
            startMs = startMs,
            endMs = startMs, // fixed up in parse()
            words = wordSegments,
        )
    }

    private fun toMs(match: MatchResult): Long {
        val (m, s, frac) = match.destructured
        // frac: 1 digit = tenths, 2 = centiseconds, 3 = milliseconds.
        val fracMs = when (frac.length) {
            0 -> 0L
            1 -> (frac[0] - '0') * 100L
            2 -> (frac[0] - '0') * 100L + (frac[1] - '0') * 10L
            3 -> (frac[0] - '0') * 100L + (frac[1] - '0') * 10L + (frac[2] - '0')
            else -> 0L
        }
        return m.toLong() * 60_000L + s.toLong() * 1_000L + fracMs
    }

    private const val DEFAULT_LINE_MS = 5_000L
}
