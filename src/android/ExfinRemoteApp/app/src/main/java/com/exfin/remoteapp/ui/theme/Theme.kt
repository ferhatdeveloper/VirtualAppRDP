package com.exfin.remoteapp.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Bg = Color(0xFF0B1220)
private val Panel = Color(0xFF121A2B)
private val Accent = Color(0xFF3B9EFF)
private val Text = Color(0xFFE8EEF8)
private val Danger = Color(0xFFF87171)
private val Ok = Color(0xFF34D399)

private val DarkColors = darkColorScheme(
    primary = Accent,
    onPrimary = Color(0xFF0B1220),
    secondary = Ok,
    background = Bg,
    onBackground = Text,
    surface = Panel,
    onSurface = Text,
    surfaceVariant = Color(0xFF172033),
    onSurfaceVariant = Color(0xFF93A0B8),
    error = Danger,
    outline = Color(0xFF243049)
)

@Composable
fun ExfinTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColors,
        content = content
    )
}
