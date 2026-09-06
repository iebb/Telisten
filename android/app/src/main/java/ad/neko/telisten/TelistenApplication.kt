package ad.neko.telisten

import android.app.Application
import ad.neko.telisten.data.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class TelistenApplication : Application() {
    var broadcast: ad.neko.telisten.player.BroadcastProcessor? = null
    private val preferences by lazy { getSharedPreferences("accounts", MODE_PRIVATE) }
    var accounts: List<Account>
        get() = runCatching { Json.decodeFromString<List<Account>>(preferences.getString("list", "[]")!!) }.getOrDefault(emptyList())
        set(value) { preferences.edit().putString("list", Json.encodeToString(value)).apply() }
    var activeId: String
        get() = preferences.getString("active", null) ?: java.util.UUID.randomUUID().toString().also { id ->
            preferences.edit().putString("active", id).apply(); accounts = accounts + Account(id)
        }
        set(value) { preferences.edit().putString("active", value).apply() }
    lateinit var store: LibraryStore
        private set
    val repository: TelegramRepository get() = currentRepository ?: TelegramRepository(this, store).also { currentRepository = it }
    private var currentRepository: TelegramRepository? = null
    override fun onCreate() { super.onCreate(); store = LibraryStore(this, activeId) }
    suspend fun switchAccount(id: String) {
        currentRepository?.close(); currentRepository = null; activeId = id; store = LibraryStore(this, id)
    }
}
