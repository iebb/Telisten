package ad.neko.telisten.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

private val Light = lightColorScheme(
    primary = Color(0xFF23695C), onPrimary = Color.White,
    primaryContainer = Color(0xFFDCEFE8), onPrimaryContainer = Color(0xFF174C42),
    secondary = Color(0xFF52635D), secondaryContainer = Color(0xFFE6ECE8),
    onSecondaryContainer = Color(0xFF303E38),
    tertiary = Color(0xFF4D6377), tertiaryContainer = Color(0xFFE0EAF3),
    background = Color(0xFFFAFBFA), onBackground = Color(0xFF202521),
    surface = Color(0xFFFAFBFA), onSurface = Color(0xFF202521),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color(0xFFF4F6F4),
    surfaceContainer = Color(0xFFEEF1EE), surfaceContainerHigh = Color(0xFFE7ECE8),
    surfaceVariant = Color(0xFFE7ECE8), onSurfaceVariant = Color(0xFF5E6962),
    outline = Color(0xFF77827A), outlineVariant = Color(0xFFDDE3DD),
)
private val Dark = darkColorScheme(
    primary = Color(0xFF94D3BD), onPrimary = Color(0xFF08382C),
    primaryContainer = Color(0xFF214C3E), onPrimaryContainer = Color(0xFFB5F0D7),
    secondary = Color(0xFFB5C8BC), secondaryContainer = Color(0xFF303E35),
    onSecondaryContainer = Color(0xFFD5E5DA),
    tertiary = Color(0xFFADC8DE), tertiaryContainer = Color(0xFF2C4355),
    background = Color(0xFF111512), onBackground = Color(0xFFE0E6E0),
    surface = Color(0xFF111512), onSurface = Color(0xFFE0E6E0),
    surfaceContainerLowest = Color(0xFF0B100C), surfaceContainerLow = Color(0xFF181D19),
    surfaceContainer = Color(0xFF202620), surfaceContainerHigh = Color(0xFF293029),
    surfaceVariant = Color(0xFF293029), onSurfaceVariant = Color(0xFFADB9AE),
    outline = Color(0xFF7C8A7E), outlineVariant = Color(0xFF354037),
)

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable fun TelistenTheme(content: @Composable () -> Unit) {
    MaterialExpressiveTheme(
        colorScheme = if (isSystemInDarkTheme()) Dark else Light,
        typography = Typography(
            headlineLarge = TextStyle(fontSize = 26.sp, lineHeight = 32.sp, fontWeight = FontWeight.SemiBold),
            headlineMedium = TextStyle(fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold),
            titleLarge = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold),
            titleMedium = TextStyle(fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium),
            titleSmall = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium),
            bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 22.sp),
            bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
            bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 17.sp),
        ),
        content = content,
    )
}
