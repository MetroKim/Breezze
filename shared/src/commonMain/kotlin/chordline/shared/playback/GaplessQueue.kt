/*
 * Chordline — GaplessQueue.
 *
 * BitChord's gapless playback: the next track is resolved and preloaded
 * before the current one finishes, so playback never slips into silence.
 */
package chordline.shared.playback

import chordline.shared.model.Track
import chordline.shared.sources.SourceRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

class GaplessQueue(
    private val scope: CoroutineScope,
    private val registry: SourceRegistry,
) {
    private val queue = ArrayDeque<Track>()
    private var preloadJob: kotlinx.coroutines.Job? = null

    /** The preloaded (stream-resolved) next track, if ready. */
    @Volatile
    var preloaded: Track? = null
        private set

    fun enqueue(track: Track) {
        queue.addLast(track)
        maybePreloadNext()
    }

    fun enqueueAll(tracks: List<Track>) {
        queue.addAll(tracks)
        maybePreloadNext()
    }

    fun peekNext(): Track? = queue.firstOrNull()

    /** Pops the next track, returning the already-preloaded one when available. */
    suspend fun popNext(): Track? {
        preloadJob?.join() // wait for in-flight resolution before swapping
        val next = preloaded ?: queue.removeFirstOrNull()?.let { resolve(it) }
        preloaded = null
        maybePreloadNext()
        return next
    }

    private fun maybePreloadNext() {
        if (preloaded != null || queue.isEmpty()) return
        val candidate = queue.first()
        preloadJob = scope.launch {
            preloaded = resolve(candidate)
        }
    }

    private suspend fun resolve(track: Track): Track =
        registry.get("local")?.resolveStream(track) ?: track
}
