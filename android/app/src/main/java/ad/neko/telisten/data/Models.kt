package ad.neko.telisten.data

import kotlinx.serialization.Serializable

@Serializable
data class Track(
    val id: String, val chatId: Long, val messageId: Long, val fileId: Int,
    val remoteId: String, val title: String, val artist: String, val fileName: String,
    val duration: Int, val size: Long, val artwork: String? = null,
    val votes: Int = 0, val voted: Boolean = false,
)
@Serializable
data class MusicChat(val id: Long, val title: String, val channel: Boolean = false, val callId: Int = 0)
@Serializable
data class Account(val id: String, val name: String = "New account")
@Serializable
data class SearchBot(val username: String, val prefix: String = "", val suffix: String = "") {
    fun command(query: String) = prefix + query.trim() + suffix
}
@Serializable
data class LyricLine(val seconds: Double? = null, val text: String)
@Serializable
data class Lyrics(val source: String, val lines: List<LyricLine>, val title: String = "", val artist: String = "")
enum class PlaybackMode(val label: String) { ORDER("In order"), SHUFFLE("Shuffle"), REVERSE("Reverse order"), REPEAT_ONE("Repeat one") }
data class MusicPage(val tracks: List<Track>, val cursor: String)
data class AuthState(val step: String = "connecting", val hint: String = "Connecting to Telegram", val link: String = "")
fun timeLabel(seconds: Long): String = "%d:%02d".format(seconds.coerceAtLeast(0) / 60, seconds.coerceAtLeast(0) % 60)
