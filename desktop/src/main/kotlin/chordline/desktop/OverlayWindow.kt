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
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.rememberWindowState
import chordline.sharedui.player.PlayerBar
import chordline.sharedui.player.PlayerBarState

/**
 * Composable overlay window. Host inside the desktop application block;
 * `isUndecorated = true` + `alwaysOnTop = true` keeps the mini-player
 * floating above every other window, mirroring Liner's overlay player.
 */
@Composable
fun OverlayWindow(
    state: PlayerBarState,
    onTogglePlayPause: () -> Unit,
    onDismiss: () -> Unit,
) {
    val windowState = rememberWindowState(
        width = 360.dp,
        height = 120.dp,
        position = WindowPosition(1200.dp, 800.dp),
    )

    Window(
        title = "Chordline Overlay",
        state = windowState,
        undecorated = true,
        alwaysOnTop = true,
        transparent = true,
        resizable = false,
        onCloseRequest = onDismiss,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xB30D0D10)) // frosted-glass fallback
                .padding(12.dp),
        ) {
            PlayerBar(state = state, onTogglePlayPause = onTogglePlayPause)
            Text("Chordline overlay", color = Color(0x99F5F5F7), fontSize = 10.sp)
        }
    }
}
