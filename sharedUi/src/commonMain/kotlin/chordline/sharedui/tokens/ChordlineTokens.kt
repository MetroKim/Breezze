/*
 * Chordline — design tokens.
 *
 * BitChord's Telegram-style frosted-glass bars (via Haze) meet Liner's
 * documented glass surfaces and motion tokens. All surfaces consume these
 * tokens; no screen hardcodes colors.
 */
package chordline.sharedui.tokens

import androidx.compose.ui.graphics.Color

/** Core palette. */
object ChordlineColors {
    val Accent = Color(0xFF7A4DFF)
    val AccentDim = Color(0xFF534DFF)
    val Surface = Color(0xFF0D0D10)
    val SurfaceGlass = Color(0xB30D0D10) // 70 % opaque — frosted glass
    val OnSurface = Color(0xFFF5F5F7)
    val OnSurfaceDim = Color(0x99F5F5F7)
    val Outline = Color(0x1FF5F5F7)
}

/** Motion tokens (durations in ms) — mirrors Liner's DESIGN.md guidance. */
object ChordlineMotion {
    const val Instant = 100
    const val Fast = 200
    const val Normal = 350
    const val Slow = 600

    /** Standard easing for lyric lines / player transitions. */
    // Usage: CubicBezierEasing(0.4f, 0.0f, 0.2f, 1f)
    const val StandardEasingControlPoints = "0.4, 0.0, 0.2, 1.0"
}

/** Corner radii for glass surfaces. */
object ChordlineRadius {
    const val Player = 28
    const val Card = 18
    const val Chip = 999
}
