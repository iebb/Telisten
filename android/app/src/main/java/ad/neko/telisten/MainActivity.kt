package ad.neko.telisten

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.viewmodel.compose.viewModel
import ad.neko.telisten.ui.TelistenTheme
import ad.neko.telisten.ui.TelistenApp
import ad.neko.telisten.ui.AppModel

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TelistenTheme {
                val model: AppModel = viewModel()
                androidx.compose.runtime.LaunchedEffect(Unit) { if (BuildConfig.DEBUG && intent.getBooleanExtra("demo", false)) { model.enableDemo(); intent.removeExtra("demo") } }
                TelistenApp(model)
            }
        }
    }
}
