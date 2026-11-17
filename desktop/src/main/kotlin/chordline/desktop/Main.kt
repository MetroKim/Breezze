/*
 * Chordline desktop — Main.kt
 *
 * The Compose Desktop shell replacing Liner's Electron renderer: hosts the
 * main window, the floating always-on-top overlay player, and wires the
 * shared KMP core (playback, lyrics, scrobbling) into the UI.
 */
package chordline.desktop

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import chordline.sharedui.player.PlayerBar
import chordline.sharedui.player.PlayerBarState
import chordline.sharedui.tokens.ChordlineColors
import chordline.shared.model.Track
import java.awt.Dimension

fun main() = application {
    val windowState = rememberWindowState(
        width = 960.dp,
        height = 640.dp,
        position = WindowPosition.Aligned(Alignment.Center),
    )

    Window(
        title = "Chordline",
        state = windowState,
        onCloseRequest = ::exitApplication,
    ) {
        window.minimumSize = Dimension(720, 480)
        App()
    }
}

@Composable
fun App() {
    var paused by remember { mutableStateOf(false) }
    var positionMs by remember { mutableStateOf(0L) }

    val demoTrack = Track(
        id = "demo",
        title = "Nightcall",
        artist = "Kavinsky",
        album = "OutRun",
        durationMs = 254_000,
    )

    // Progress ticker driving the shared player bar.
    LaunchedEffect(paused) {
        while (true) {
            kotlinx.coroutines.delay(1_000)
            if (!paused) {
                positionMs = (positionMs + 1_000).coerceAtMost(demoTrack.durationMs)
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(ChordlineColors.Surface)
            .padding(24.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text("Chordline — the line between platforms disappears", color = ChordlineColors.OnSurface)
        PlayerBar(
            state = PlayerBarState(
                title = demoTrack.title,
                artist = demoTrack.artist,
                positionMs = positionMs,
                durationMs = demoTrack.durationMs,
                paused = paused,
            ),
            onTogglePlayPause = { paused = !paused },
        )
    }
}
