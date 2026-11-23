/*
 * Chordline — glass surfaces library.
 *
 * BitChord's frosted-glass translucent bars and Liner's glass-surface
 * building blocks, expressed as reusable composables so every surface
 * renders identically.
 */
package chordline.sharedui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import chordline.sharedui.tokens.ChordlineColors
import chordline.sharedui.tokens.ChordlineRadius

/**
 * A frosted-glass translucent container — the signature surface of both
 * parents' player bars. On Android a real blur (Haze/RenderEffect) can be
 * layered beneath; on desktop the translucent gradient is the fallback.
 */
@Composable
fun GlassBar(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(ChordlineRadius.Player.dp))
            .background(
                Brush.verticalGradient(
                    listOf(ChordlineColors.SurfaceGlass, ChordlineColors.SurfaceGlass),
                ),
            )
            .padding(horizontal = 20.dp, vertical = 14.dp),
    ) {
        content()
    }
}

/** Accent progress tint used by player bars and sliders. */
val PlayerProgressTint: Color get() = ChordlineColors.Accent
