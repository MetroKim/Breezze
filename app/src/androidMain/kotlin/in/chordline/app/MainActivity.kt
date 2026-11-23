/*
 * Chordline Android — MainActivity.
 *
 * BitChord's Android heritage lives here: the same shared KMP core and
 * sharedUi design system drive the mobile surface.
 */
package in.chordline.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import chordline.sharedui.player.PlayerBar
import chordline.sharedui.player.PlayerBarState
import chordline.sharedui.tokens.ChordlineColors
import chordline.shared.model.Track
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            ChordlineApp()
        }
    }
}

@Composable
fun ChordlineApp() {
    var paused by remember { mutableStateOf(false) }
    var positionMs by remember { mutableStateOf(0L) }

    val demoTrack = Track(
        id = "demo",
        title = "Nightcall",
        artist = "Kavinsky",
        album = "OutRun",
        durationMs = 254_000,
    )

    LaunchedEffect(paused) {
        while (true) {
            delay(1_000)
            if (!paused) {
                positionMs = (positionMs + 1_000).coerceAtMost(demoTrack.durationMs)
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(ChordlineColors.Surface)
            .padding(20.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text("Chordline", color = ChordlineColors.OnSurface)
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
