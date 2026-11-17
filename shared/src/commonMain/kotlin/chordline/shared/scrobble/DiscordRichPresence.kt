/*
 * Chordline — Discord Rich Presence.
 *
 * BitChord shows live track/artist/album and progress via Discord Rich
 * Presence (in-app login). The shared layer exposes the presence state;
 * platforms own the actual IPC connection (Discord only ships clients for
 * Android and desktop).
 */
package chordline.shared.scrobble

import chordline.shared.model.Track

/** Rich presence state pushed to the platform's Discord client. */
data class DiscordPresence(
    val trackId: String,
    val title: String,
    val artist: String,
    val album: String?,
    val artworkUrl: String?,
    val positionMs: Long,
    val durationMs: Long,
    val paused: Boolean,
)

/** Pushes presence updates to Discord. */
interface DiscordRpc {
    fun update(presence: DiscordPresence)
    fun clear()
}

class DiscordRichPresence(private val rpc: DiscordRpc) {
    private var lastTrackId: String? = null

    /** Call on playback position updates. */
    fun onPosition(track: Track, positionMs: Long, paused: Boolean) {
        if (!paused) {
            lastTrackId = track.id
        }
        rpc.update(
            DiscordPresence(
                trackId = track.id,
                title = track.title,
                artist = track.artist,
                album = track.album,
                artworkUrl = track.artworkUrl,
                positionMs = positionMs,
                durationMs = track.durationMs,
                paused = paused,
            ),
        )
    }

    /** Call when playback stops entirely. */
    fun onStopped() {
        lastTrackId = null
        rpc.clear()
    }
}
