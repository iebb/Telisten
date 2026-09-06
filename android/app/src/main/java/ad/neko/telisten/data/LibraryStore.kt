package ad.neko.telisten.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Separate preferences and media for each Telegram authorization; never backed up. */
class LibraryStore(context: Context, val accountId: String) {
    val root = File(context.filesDir, "accounts/$accountId").apply { mkdirs() }
    val media = File(root, "downloads").apply { mkdirs() }
    val lyricsDir = File(root, "lyrics").apply { mkdirs() }
    val prefs = context.getSharedPreferences("library-$accountId", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    var tracks: List<Track>
        get() = runCatching { json.decodeFromString<List<Track>>(prefs.getString("tracks", "[]")!!) }.getOrDefault(emptyList())
        set(value) { prefs.edit().putString("tracks", json.encodeToString(value)).apply() }
    var favorites: Set<String>
        get() = prefs.getStringSet("favorites", emptySet())!!.toSet()
        set(value) { prefs.edit().putStringSet("favorites", value.toSet()).apply() }
    var savedChats: Set<String>
        get() = prefs.getStringSet("savedChats", emptySet())!!.toSet()
        set(value) { prefs.edit().putStringSet("savedChats", value.toSet()).apply() }
    var playlistOrders: Map<String, List<String>>
        get() = runCatching { json.decodeFromString<Map<String, List<String>>>(prefs.getString("playlistOrders", "{}")!!) }.getOrDefault(emptyMap())
        set(value) { prefs.edit().putString("playlistOrders", json.encodeToString(value)).apply() }
    var bots: List<SearchBot>
        get() = runCatching { json.decodeFromString<List<SearchBot>>(prefs.getString("bots", "[]")!!) }.getOrDefault(emptyList())
        set(value) { prefs.edit().putString("bots", json.encodeToString(value)).apply() }
    var cacheLimit: Long
        get() = prefs.getLong("cacheLimit", 2L * 1024 * 1024 * 1024)
        set(value) { prefs.edit().putLong("cacheLimit", value).apply() }
    var lyricsServer: String
        get() = prefs.getString("lyricsServer", "https://lrclib.net")!!
        set(value) { require(value.startsWith("https://")); prefs.edit().putString("lyricsServer", value.trimEnd('/')).apply() }
    var playlistFolderName: String
        get() = PlaylistFolderConfiguration.normalizedName(prefs.getString("playlistFolderName", "")!!)
            ?: PlaylistFolderConfiguration.DEFAULT_NAME
        set(value) {
            val name = requireNotNull(PlaylistFolderConfiguration.normalizedName(value)) { "Enter a folder name of 1–12 characters, without line breaks." }
            prefs.edit().putString("playlistFolderName", name).apply()
        }
    fun remember(items: List<Track>) { tracks = (items + tracks).distinctBy { it.id } }
    private fun safeKey(id: String) = java.security.MessageDigest.getInstance("SHA-256").digest(id.toByteArray()).joinToString("") { "%02x".format(it) }
    fun file(track: Track) = File(media, safeKey(track.id) + ".audio")
    fun downloaded(track: Track) = file(track).isFile
    fun touch(track: Track) { file(track).setLastModified(System.currentTimeMillis()) }
    val streamBudget: Long get() = minOf(256L * 1024 * 1024, cacheLimit / 4)
    val downloadBudget: Long get() = cacheLimit - streamBudget
    fun streamBytes() = File(root, "telegram-files").walkTopDown().filter { it.isFile }.sumOf { it.length() }
    fun usedBytes() = downloadedBytes() + streamBytes()
    private fun downloadedBytes() = media.listFiles()?.filter { it.extension == "audio" }?.sumOf { it.length() } ?: 0L
    fun prune(protectedId: String? = null) {
        var used = downloadedBytes()
        media.listFiles()?.filter { it.extension == "audio" && it.nameWithoutExtension != protectedId?.let(::safeKey) }
            ?.sortedBy { it.lastModified() }?.forEach { if (used > downloadBudget) { val size = it.length(); if (it.delete()) used -= size } }
    }
    fun readLyrics(track: Track): Lyrics? = runCatching { json.decodeFromString<Lyrics>(File(lyricsDir, safeKey(track.id)).readText()) }.getOrNull()
    fun saveLyrics(track: Track, lyrics: Lyrics) { File(lyricsDir, safeKey(track.id)).writeText(json.encodeToString(lyrics)) }
}

/** The TDLib database key is wrapped by a non-exportable Android Keystore AES key. */
class SessionKeys(private val context: Context) {
    fun databaseKey(account: String): ByteArray {
        val alias = "telisten.database.$account"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val key = (store.getKey(alias, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
        val prefs = context.getSharedPreferences("session-keys", Context.MODE_PRIVATE)
        val encoded = prefs.getString(account, null)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        if (encoded != null) {
            val bytes = Base64.decode(encoded, Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            return cipher.doFinal(bytes.copyOfRange(12, bytes.size))
        }
        val secret = ByteArray(32).also { java.security.SecureRandom().nextBytes(it) }
        cipher.init(Cipher.ENCRYPT_MODE, key)
        prefs.edit().putString(account, Base64.encodeToString(cipher.iv + cipher.doFinal(secret), Base64.NO_WRAP)).commit()
        return secret
    }
    fun remove(account: String) {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry("telisten.database.$account") }
        context.getSharedPreferences("session-keys", Context.MODE_PRIVATE).edit().remove(account).apply()
    }
}
