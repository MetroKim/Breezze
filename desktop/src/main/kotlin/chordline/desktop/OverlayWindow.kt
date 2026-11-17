/*
 * Chordline desktop — OverlayWindow.kt
 *
 * Liner's floating always-on-top overlay player, ported to Compose Desktop:
 * a small transparent window pinned above all others with the current
 * track, position and play/pause control.
 */
package chordline.desktop

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.rememberWindowState
import chordline.sharedui.player.PlayerBar
import chordline.sharedui.player.PlayerBarState

/**
 * Opens the floating overlay player. Call from the main window with the
 * current [PlayerBarState] and the play/pause toggle callback.
 */
fun overlayWindow(
    state: PlayerBarState,
    onTogglePlayPause: () -> Unit,
    onDismiss: () -> Unit,
): WindowDescription = WindowDescription(
    title = "Chordline Overlay",
    width = 360.dp.value,
    height = 96.dp.value,
    alwaysOnTop = true,
    undecorated = true,
    onDismiss = onDismiss,
) {
    OverlayContent(state, onTogglePlayPause)
}

@Composable
private fun OverlayContent(state: PlayerBarState, onTogglePlayPause: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xB30D0D10)) // frosted-glass fallback
            .padding(12.dp),
    ) {
        PlayerBar(state = state, onTogglePlayPause = onTogglePlayPause)
        Text(
            "Chordline overlay",
            color = Color(0x99F5F5F7),
            fontSize = androidx.compose.ui.unit.TextUnit.Unspecified,
        )
    }
}

/** Serializable window description consumed by the desktop shell. */
data class WindowDescription(
    val title: String,
    val width: Float,
    val height: Float,
    val alwaysOnTop: Boolean,
    val undecorated: Boolean,
    val onDismiss: () -> Unit,
    val content: @Composable () -> Unit,
)
