/*
 * Chordline — SleepTimer.
 *
 * BitChord's sleep timer: fixed presets or "stop after this track".
 */
package chordline.shared.playback

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class SleepTimer(private val scope: CoroutineScope) {
    /** Standard presets, in minutes. */
    enum class Preset(val minutes: Int) { M10(10), M20(20), M30(30), M60(60) }

    sealed interface Event {
        data object StopAfterTrack : Event
        data object Timeout : Event
    }

    private var job: Job? = null

    @Volatile
    var mode: Mode = Mode.OFF
        private set

    @Volatile
    var endsAtMs: Long? = null
        private set

    enum class Mode { OFF, PRESET, AFTER_TRACK }

    fun startPreset(preset: Preset) {
        job?.cancel()
        mode = Mode.PRESET
        val duration = preset.minutes * 60_000L
        endsAtMs = now() + duration
        job = scope.launch {
            delay(duration)
            mode = Mode.OFF
            endsAtMs = null
            onEvent?.invoke(Event.Timeout)
        }
    }

    fun stopAfterTrack() {
        job?.cancel()
        mode = Mode.AFTER_TRACK
        endsAtMs = null
    }

    fun cancel() {
        job?.cancel()
        mode = Mode.OFF
        endsAtMs = null
    }

    /** Called by the player when a track finishes; returns true if playback should stop. */
    fun onTrackEnded(): Boolean {
        if (mode != Mode.AFTER_TRACK) return false
        cancel()
        return true
    }

    var onEvent: ((Event) -> Unit)? = null

    /** Overridable clock for tests. */
    var now: () -> Long = { System.currentTimeMillis() }
}
