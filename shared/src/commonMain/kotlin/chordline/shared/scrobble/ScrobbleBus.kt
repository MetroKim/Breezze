/*
 * Chordline — scrobbling.
 *
 * BitChord scrobbles to Last.fm and ListenBrainz. The ScrobbleBus is the
 * shared sink: it enforces the 30-second minimum-play rule both platforms
 * require before a play counts as a scrobble.
 */
package chordline.shared.scrobble

import chordline.shared.model.Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A scrobbling destination (Last.fm, ListenBrainz). */
interface Scrobbler {
    val id: String

    /** Fire-and-forget submit; implement with retries as needed. */
    suspend fun submit(track: Track, playedAtEpochMs: Long)
}

class ScrobbleBus(private val scope: CoroutineScope) {
    private val scrobblers = mutableListOf<Scrobbler>()
    private val pending = mutableMapOf<String, Pending>()

    private class Pending(
        val track: Track,
        var elapsedMs: Long = 0L,
        var lastTickMs: Long? = null,
        var submitted: Boolean = false,
    )

    fun register(scrobbler: Scrobbler) {
        scrobblers.add(scrobbler)
    }

    /** Call when a track starts playing. */
    fun onPlay(track: Track, nowEpochMs: Long) {
        pending[track.id] = Pending(track).apply { lastTickMs = nowEpochMs }
    }

    /**
     * Call periodically (e.g. every second) while playing.
     * Submits to all registered scrobblers once 30 s has elapsed.
     */
    fun onTick(trackId: String, nowEpochMs: Long) {
        val p = pending[trackId] ?: return
        val last = p.lastTickMs
        if (last != null) p.elapsedMs += (nowEpochMs - last).coerceAtMost(2_000)
        p.lastTickMs = nowEpochMs

        if (!p.submitted && p.elapsedMs >= MIN_PLAY_MS) {
            p.submitted = true
            val track = p.track
            scope.launch {
                scrobblers.forEach { s -> runCatching { s.submit(track, nowEpochMs) } }
            }
        }
    }

    /** Call when a track stops or is skipped. */
    fun onStop(trackId: String) {
        pending.remove(trackId)
    }

    companion object {
        /** Both Last.fm and ListenBrainz require >= 30 s played. */
        const val MIN_PLAY_MS = 30_000L
    }
}
