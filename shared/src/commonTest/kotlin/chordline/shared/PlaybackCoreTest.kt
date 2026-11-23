package chordline.shared

import chordline.shared.playback.Automix
import chordline.shared.playback.CrossfadeController
import chordline.shared.playback.GaplessQueue
import chordline.shared.playback.SleepTimer
import chordline.shared.model.Track
import chordline.shared.sources.SourceRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PlaybackCoreTest {

    // ---- Automix ----------------------------------------------------------

    @Test
    fun automix_beat_matches_close_bpms() {
        val mix = Automix()
        val t = mix.plan(
            Automix.TrackAnalysis(bpm = 120, energy = 0.5),
            Automix.TrackAnalysis(bpm = 121, energy = 0.5),
        )
        assertTrue(t.beatMatched)
        assertTrue(t.tempoFactor in 0.99..1.01)
        assertFalse(t.doubleTimeFold)
    }

    @Test
    fun automix_folds_double_time() {
        val mix = Automix()
        val t = mix.plan(
            Automix.TrackAnalysis(bpm = 120, energy = 0.3),
            Automix.TrackAnalysis(bpm = 60, energy = 0.3),
        )
        assertTrue(t.beatMatched)
        assertTrue(t.doubleTimeFold)
    }

    @Test
    fun automix_no_match_when_bpms_far_apart() {
        val mix = Automix()
        val t = mix.plan(
            Automix.TrackAnalysis(bpm = 90, energy = 0.2),
            Automix.TrackAnalysis(bpm = 160, energy = 0.9),
        )
        assertFalse(t.beatMatched)
        assertEquals(1.0, t.tempoFactor)
    }

    @Test
    fun automix_transition_scales_with_energy() {
        val mix = Automix(baseTransitionMs = 4_000)
        val low = mix.plan(
            Automix.TrackAnalysis(bpm = 120, energy = 0.0),
            Automix.TrackAnalysis(bpm = 120, energy = 0.0),
        )
        val high = mix.plan(
            Automix.TrackAnalysis(bpm = 120, energy = 1.0),
            Automix.TrackAnalysis(bpm = 120, energy = 1.0),
        )
        assertTrue(high.transitionMs > low.transitionMs)
    }

    // ---- GaplessQueue -----------------------------------------------------

    @Test
    fun gapless_queue_preloads_next() = runTest {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val registry = SourceRegistry()
        val queue = GaplessQueue(scope, registry)
        queue.enqueue(track("a"))
        queue.enqueue(track("b"))

        val first = queue.popNext()
        assertEquals("a", first?.id)

        // popNext awaits the in-flight preload job; second is ready.
        val second = queue.popNext()
        assertEquals("b", second?.id)
        scope.cancel()
    }

    @Test
    fun gapless_queue_empty_returns_null() = runTest {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val queue = GaplessQueue(scope, SourceRegistry())
        assertNull(queue.popNext())
        scope.cancel()
    }

    // ---- SleepTimer --------------------------------------------------------

    @Test
    fun sleep_timer_stop_after_track_fires_once() = runTest {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val timer = SleepTimer(scope)
        timer.stopAfterTrack()

        assertTrue(timer.onTrackEnded())
        assertFalse(timer.onTrackEnded()) // already consumed
        scope.cancel()
    }

    private fun track(id: String) = Track(id = id, title = "T-$id", artist = "A", durationMs = 1_000)
}
