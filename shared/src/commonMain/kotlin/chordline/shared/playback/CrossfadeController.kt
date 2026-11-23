/*
 * Chordline — CrossfadeController.
 *
 * BitChord's "gapless playback with true crossfade, adjustable 0–12 s".
 * Fires the crossfade trigger exactly `crossfadeMs` before a track's end,
 * so the platform player can blend the outgoing and incoming streams.
 */
package chordline.shared.playback

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Watches playback progress and triggers the crossfade window.
 *
 * The platform player reports [onProgress]; this controller decides when the
 * fade should begin and emits events for the renderer/player to act on.
 */
class CrossfadeController(
    private val scope: CoroutineScope,
    private val crossfadeMs: Long = 0L,
) {
    /** Emitted exactly `crossfadeMs` before the end of the current track. */
    val events = kotlinx.coroutines.channels.Channel<CrossfadeEvent>(Channel.CONFLATED)

    private var job: Job? = null
    private var triggeredForTrack: String? = null

    /** True when the next track should be faded in while this one fades out. */
    val active: Boolean get() = crossfadeMs > 0

    fun start(trackId: String, durationMs: Long) {
        job?.cancel()
        triggeredForTrack = null
        if (!active || durationMs <= 0) return

        job = scope.launch {
            delay((durationMs - crossfadeMs).coerceAtLeast(0))
            if (triggeredForTrack != trackId) {
                triggeredForTrack = trackId
                events.trySend(CrossfadeEvent(trackId, crossfadeMs))
            }
            delay(crossfadeMs)
            events.trySend(CrossfadeEvent(trackId, 0L)) // fade-out complete
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    data class CrossfadeEvent(val trackId: String, val remainingMs: Long)
}
