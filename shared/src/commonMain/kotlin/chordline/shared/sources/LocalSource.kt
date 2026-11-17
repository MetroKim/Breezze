/*
 * Chordline — LocalSource.
 *
 * Liner's `liner-local://` local tracks protocol, ported to the shared KMP
 * core as a first-class SourcePlugin: imported audio files are scanned,
 * modeled as tracks and served through the chordline-local:// scheme.
 */
package chordline.shared.sources

import chordline.shared.model.Track

/** The custom scheme used for local files on every platform. */
const val CHORDLINE_LOCAL_SCHEME = "chordline-local"

class LocalSource(
    /** Maps a local media id to its absolute file path. */
    private val pathResolver: (String) -> String? = { null },
) : SourcePlugin {
    override val id = "local"
    override val displayName = "Local files"

    override suspend fun ping(): Boolean = true

    override suspend fun search(query: String): List<Track> =
        emptyList() // scanning is platform-specific; the app layer feeds results

    /**
     * Rewrites a track into a chordline-local:// URL the platform player can
     * handle. Format: chordline-local://<mediaId>
     */
    fun localUrl(mediaId: String): String = "$CHORDLINE_LOCAL_SCHEME://$mediaId"

    fun resolveUrl(track: Track): String? {
        if (!track.streamUrl.startsWith(CHORDLINE_LOCAL_SCHEME)) return null
        val mediaId = track.streamUrl.removePrefix("$CHORDLINE_LOCAL_SCHEME://")
        return pathResolver(mediaId)
    }
}
