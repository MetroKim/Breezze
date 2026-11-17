package chordline.shared

import chordline.shared.model.Artist
import chordline.shared.model.AudioQuality
import chordline.shared.model.Playlist
import chordline.shared.model.Track
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class SharedModelTest {

    private fun track() = Track(
        id = "t1",
        title = "Nightcall",
        artist = "Kavinsky",
        album = "OutRun",
        durationMs = 254_000,
        quality = AudioQuality.LOSSLESS,
    )

    @Test
    fun track_serializes_round_trip() {
        val json = Json.encodeToString(Track.serializer(), track())
        val decoded = Json.decodeFromString(Track.serializer(), json)
        assertEquals(track(), decoded)
    }

    @Test
    fun track_defaults_are_sensible() {
        val t = Track(id = "x", title = "T", artist = "A", durationMs = 1)
        assertEquals(AudioQuality.STANDARD, t.quality)
        assertEquals(null, t.streamUrl)
        assertEquals(false, t.fromLosslessSource)
    }

    @Test
    fun playlist_and_artist_serialize() {
        val p = Playlist(id = "p1", name = "Late Night Drive", trackIds = listOf("t1"))
        val a = Artist(id = "a1", name = "Kavinsky")
        assertTrue(Json.encodeToString(Playlist.serializer(), p).contains("Late Night Drive"))
        assertNotNull(Json.decodeFromString(Artist.serializer(), Json.encodeToString(Artist.serializer(), a)))
    }
}
