/*
 * Chordline — PlayerBar widget.
 *
 * The shared now-playing surface: frosted-glass bar with track info and
 * position. Used by the desktop shell and the Android app.
 */
package chordline.sharedui.player

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import chordline.sharedui.components.GlassBar
import chordline.sharedui.tokens.ChordlineColors
import chordline.sharedui.tokens.ChordlineMotion

data class PlayerBarState(
    val title: String,
    val artist: String,
    val positionMs: Long,
    val durationMs: Long,
    val paused: Boolean,
)

@Composable
fun PlayerBar(
    state: PlayerBarState,
    onTogglePlayPause: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val progress by animateFloatAsState(
        targetValue = if (state.durationMs > 0) {
            (state.positionMs.toFloat() / state.durationMs).coerceIn(0f, 1f)
        } else 0f,
        animationSpec = tween(ChordlineMotion.Fast),
        label = "progress",
    )

    GlassBar(modifier = modifier) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = if (state.paused) "▶" else "⏸",
                    modifier = Modifier.clickable(onClick = onTogglePlayPause),
                    color = ChordlineColors.OnSurface,
                )
                Spacer(Modifier.width(14.dp))
                Column {
                    Text(
                        state.title,
                        color = ChordlineColors.OnSurface,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(state.artist, color = ChordlineColors.OnSurfaceDim)
                }
            }
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth().height(3.dp),
                color = ChordlineColors.Accent,
            )
        }
    }
}
