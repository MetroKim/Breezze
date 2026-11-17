/*
 * Chordline — LyricsPipeline.
 *
 * Unifies BitChord's multi-provider lyrics aggregation (13 providers) with
 * Liner's always-on synced lyrics: providers are tried in order of
 * preference until one returns enhanced LRC data.
 */
package chordline.shared.lyrics

import chordline.shared.model.Track

/** Fetches raw lyrics (plain LRC or enhanced LRC) for a track. */
interface LyricsProvider {
    val id: String
    /** Lower = tried first. */
    val priority: Int

    /**
     * Returns raw lyric text for the track, or null when this provider
     * has no match. Implementations must never throw for "not found".
     */
    suspend fun fetch(track: Track): String?
}

class LyricsPipeline(providers: List<LyricsProvider>) {
    private val ordered = providers.sortedBy { it.priority }

    suspend fun lyricsFor(track: Track): Lyrics? {
        for (provider in ordered) {
            val raw = runCatching { provider.fetch(track) }.getOrNull() ?: continue
            if (raw.isBlank()) continue
            // Prefer word-synced LRC; fall back to line-only.
            return LrcParser.parse(track.id, raw)
        }
        return null
    }
}
