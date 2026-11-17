/*
 * Chordline — SourcePlugin layer.
 *
 * BitChord's "pluggable module sources" meets Liner's multi-platform library
 * aggregation. A source resolves tracks and stream URLs; the registry
 * health-checks them the way BitChord health-checks module sources.
 */
package chordline.shared.sources

import chordline.shared.model.Playlist
import chordline.shared.model.Track

/** A pluggable music source. */
interface SourcePlugin {
    /** Stable identifier, e.g. "ytm", "spotify", "local". */
    val id: String

    /** Human-readable name. */
    val displayName: String

    /**
     * Health check: returns true when the source can currently serve
     * requests (auth valid, module loaded, network reachable).
     */
    suspend fun ping(): Boolean

    /** Search the source. */
    suspend fun search(query: String): List<Track>

    /** Resolve a playable stream URL for the given quality ceiling. */
    suspend fun resolveStream(track: Track): Track

    /** Fetch playlists owned/liked by the signed-in user, if any. */
    suspend fun playlists(): List<Playlist> = emptyList()
}

/** Registry of registered sources with health checks. */
class SourceRegistry {
    private val plugins = LinkedHashMap<String, SourcePlugin>()

    fun register(plugin: SourcePlugin) {
        require(plugin.id.isNotBlank()) { "Source id must not be blank" }
        plugins[plugin.id] = plugin
    }

    fun get(id: String): SourcePlugin? = plugins[id]

    fun all(): List<SourcePlugin> = plugins.values.toList()

    /** Runs a ping against every source and returns id -> healthy. */
    suspend fun healthCheck(): Map<String, Boolean> =
        plugins.mapValues { (_, p) -> runCatching { p.ping() }.getOrDefault(false) }
}
