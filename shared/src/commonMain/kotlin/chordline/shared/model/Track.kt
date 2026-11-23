/*
 * Chordline — entities layer.
 *
 * Platform-agnostic track model shared by every surface (Android, Desktop).
 * Mirrors the union of BitChord's track metadata and Liner's entity contracts:
 * quality ceiling for lossless playback, artwork for dynamic theming.
 */
package chordline.shared.model

import kotlinx.serialization.Serializable

/** Audio quality tiers, from BitChord's per-network quality ceilings. */
enum class AudioQuality {
    /** Standard platform stream (AAC/Opus). */
    STANDARD,

    /** High quality tier. */
    HIGH,

    /** Hi-Res lossless — FLAC/ALAC from a configured module source. */
    LOSSLESS,
}

/** A playable track. */
@Serializable
data class Track(
    val id: String,
    val title: String,
    val artist: String,
    val album: String? = null,
    /** Direct stream URL resolved by a [chordline.shared.sources.SourcePlugin]. */
    val streamUrl: String? = null,
    /** Duration in milliseconds. */
    val durationMs: Long,
    /** Artwork URL used for the dynamic, artwork-driven theming. */
    val artworkUrl: String? = null,
    /** Quality ceiling for this track. */
    val quality: AudioQuality = AudioQuality.STANDARD,
    /** True when resolved from a pluggable lossless module source. */
    val fromLosslessSource: Boolean = false,
)

/** A playlist aggregated from any connected platform. */
@Serializable
data class Playlist(
    val id: String,
    val name: String,
    val owner: String? = null,
    val artworkUrl: String? = null,
    val trackIds: List<String> = emptyList(),
)

/** An artist entity. */
@Serializable
data class Artist(
    val id: String,
    val name: String,
    val artworkUrl: String? = null,
)
