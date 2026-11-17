package chordline.shared

import chordline.shared.lyrics.LrcParser
import chordline.shared.lyrics.LyricsPipeline
import chordline.shared.lyrics.LyricsProvider
import chordline.shared.model.Track
import chordline.shared.scrobble.ScrobbleBus
import chordline.shared.scrobble.Scrobbler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LyricsAndScrobbleTest {

    private val sample = """
        [00:01.00]First line
        [00:03.50]Second <00:03.60>word <00:03.80>sync
        [00:06.00]Third line
    """.trimIndent()

    // ---- LrcParser --------------------------------------------------------

    @Test
    fun lrc_parses_lines_sorted_with_end_times() {
        val lyrics = LrcParser.parse("t1", sample)
        assertEquals(3, lyrics.lines.size)
        assertEquals(1_000, lyrics.lines[0].startMs)
        assertEquals(3_500, lyrics.lines[1].startMs)
        assertEquals(6_000, lyrics.lines[2].startMs)

        // Line end = next line start
        assertEquals(3_500, lyrics.lines[0].endMs)
        assertEquals(6_000, lyrics.lines[1].endMs)
    }

    @Test
    fun lrc_parses_word_level_sync() {
        val lyrics = LrcParser.parse("t1", sample)
        val second = lyrics.lines[1]
        assertEquals(2, second.words.size)
        assertEquals("word", second.words[0].text)
        assertEquals(3_600, second.words[0].startMs)
        assertEquals("sync", second.words[1].text)
        assertEquals(3_800, second.words[1].startMs)
    }

    @Test
    fun lrc_active_line_binary_search() {
        val lyrics = LrcParser.parse("t1", sample)
        assertEquals(0, lyrics.activeLineIndex(1_000))
        assertEquals(1, lyrics.activeLineIndex(3_600))
        assertEquals(2, lyrics.activeLineIndex(7_000))
        assertEquals(-1, lyrics.activeLineIndex(500))
    }

    @Test
    fun lrc_ignores_plain_text_and_metadata() {
        val lyrics = LrcParser.parse(
            "t1",
            "[ar:Artist]\n[ti:Title]\nplain junk line\n[00:01.00]Real",
        )
        assertEquals(1, lyrics.lines.size)
        assertEquals("Real", lyrics.lines[0].text)
    }

    // ---- LyricsPipeline ---------------------------------------------------

    @Test
    fun pipeline_tries_providers_by_priority() {
        val calls = mutableListOf<String>()
        val p = LyricsPipeline(
            listOf(
                object : LyricsProvider {
                    override val id = "first"
                    override val priority = 1
                    override suspend fun fetch(track: Track) = null.also { calls.add(id) }
                },
                object : LyricsProvider {
                    override val id = "second"
                    override val priority = 2
                    override suspend fun fetch(track: Track) = sample.also { calls.add(id) }
                },
            ),
        )
        val result = kotlinx.coroutines.test.runTest { p.lyricsFor(track("t1")) } as Any
        assertTrue(calls == listOf("first", "second"))
    }

    // ---- ScrobbleBus -------------------------------------------------------

    @Test
    fun scrobble_bus_enforces_30_second_rule() {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
        val submitted = mutableListOf<String>()
        val bus = ScrobbleBus(scope)
        bus.register(object : Scrobbler {
            override val id = "lastfm"
            override suspend fun submit(track: Track, playedAtEpochMs: Long) {
                submitted.add(track.id)
            }
        })

        val t = track("t1")
        bus.onPlay(t, nowEpochMs = 0)
        repeat(29) { bus.onTick("t1", nowEpochMs = (it + 1) * 1_000L) }
        assertEquals(0, submitted.size) // 29 s: below threshold

        bus.onTick("t1", nowEpochMs = 30_000L)
        assertEquals(1, submitted.size) // 30 s: fires
        scope.cancel()
    }

    private fun track(id: String) = Track(id = id, title = "T", artist = "A", durationMs = 60_000)
}
