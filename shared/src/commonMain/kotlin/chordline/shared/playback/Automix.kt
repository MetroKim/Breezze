/*
 * Chordline — Automix.
 *
 * BitChord's "Automix [Beta] — DJ-style transitions with beat-matching and
 * tempo-stretching", distilled into a deterministic, testable core:
 *
 * - BPM ratio within ±10 %  -> beat-matched transition
 * - double-time / half-time folding expands the match window
 * - transition length scales with the pair's energy (0.5–1.5 × base)
 */
package chordline.shared.playback

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

class Automix(
    /** Base transition length in ms, scaled by pair energy. */
    private val baseTransitionMs: Long = 4_000L,
) {
    /** Analyzed per-track characteristics driving the mix decision. */
    data class TrackAnalysis(val bpm: Int, val energy: Double)

    /** The transition plan for an outgoing -> incoming pair. */
    data class Transition(
        val beatMatched: Boolean,
        /** Tempo factor to apply to the incoming track: 1.0 = unchanged. */
        val tempoFactor: Double,
        /** Length of the overlap in ms. */
        val transitionMs: Long,
        /** True when the incoming track must be double-time folded to match. */
        val doubleTimeFold: Boolean,
    )

    /**
     * Plans a DJ-style transition. When BPMs are close (±10 %, after folding
     * one track by 2× or 0.5×), the mix is beat-matched and the incoming
     * tempo is stretched toward the outgoing tempo.
     */
    fun plan(outgoing: TrackAnalysis, incoming: TrackAnalysis): Transition {
        val pairs = sequenceOf(1.0, 2.0, 0.5).map { fold ->
            fold to (incoming.bpm * fold) / outgoing.bpm.toDouble()
        }
        val (bestFold, bestRatio) = pairs.minByOrNull { (_, r) -> abs(1.0 - r) }!!

        val matched = abs(1.0 - bestRatio) <= 0.10
        val energy = max(outgoing.energy, incoming.energy).coerceIn(0.0, 1.0)
        val transitionMs = (baseTransitionMs * (0.5 + energy)).roundToInt().toLong()

        return Transition(
            beatMatched = matched,
            tempoFactor = if (matched) 1.0 / bestRatio else 1.0,
            tempoFactorSetExplicitly = false, // placeholder removed below
            transitionMs = transitionMs,
            doubleTimeFold = matched && bestFold != 1.0,
        )
    }
}
