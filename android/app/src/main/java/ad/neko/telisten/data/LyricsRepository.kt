package ad.neko.telisten.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

object LrcParser {
    private val tag = Regex("\\[(\\d+):(\\d{2})(?:[.:](\\d{1,3}))?]")
    fun parse(text: String): List<LyricLine> {
        val offset = Regex("\\[offset:([+-]?\\d+)]", RegexOption.IGNORE_CASE).find(text)?.groupValues?.get(1)?.toDoubleOrNull()?.div(1000) ?: 0.0
        val synced = text.lines().flatMap { line ->
            val tags = tag.findAll(line).toList()
            val words = line.replace(tag, "").trim()
            tags.map { match ->
                val fraction = match.groupValues[3].takeIf { it.isNotEmpty() }?.let { "0.$it".toDouble() } ?: 0.0
                LyricLine((match.groupValues[1].toInt() * 60 + match.groupValues[2].toInt() + fraction + offset).coerceAtLeast(0.0), words)
            }
        }.sortedBy { it.seconds }
        return synced.ifEmpty { text.lines().filter { it.isNotBlank() && !it.matches(Regex("\\[\\w+:.*]")) }.map { LyricLine(text = it.trim()) } }
    }
}
class LyricsRepository(private val store: LibraryStore) {
    private val http = OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build()
    suspend fun find(track: Track, force: Boolean = false): List<Lyrics> = withContext(Dispatchers.IO) {
        if (!force) store.readLyrics(track)?.let { return@withContext listOf(it) }
        val base = store.lyricsServer.toHttpUrl()
        require(base.isHttps) { "Use an HTTPS lyrics server" }
        fun fetch(path: String): JsonElement? {
            val url = base.newBuilder().addPathSegments(path).addQueryParameter("track_name", track.title)
                .addQueryParameter("artist_name", track.artist).apply { if (path.endsWith("get")) addQueryParameter("duration", track.duration.toString()) }.build()
            http.newCall(Request.Builder().url(url).header("User-Agent", "Telisten/1.0 (Android)").build()).execute().use { response ->
                if (response.code == 404) return null
                check(response.isSuccessful) { "Lyrics server returned ${response.code}" }
                return response.body?.string()?.let(Json::parseToJsonElement)
            }
        }
        fun convert(value: JsonElement): Lyrics? {
            val obj = value.jsonObject
            val text = obj["syncedLyrics"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
                ?: obj["plainLyrics"]?.jsonPrimitive?.contentOrNull ?: return null
            return Lyrics(store.lyricsServer, LrcParser.parse(text), obj["trackName"]?.jsonPrimitive?.contentOrNull ?: track.title, obj["artistName"]?.jsonPrimitive?.contentOrNull ?: track.artist)
        }
        val exact = if (!force) fetch("api/get")?.let(::convert) else null
        val found = exact?.let { listOf(it) } ?: (fetch("api/search") as? JsonArray)?.mapNotNull(::convert).orEmpty()
        found.firstOrNull()?.let { store.saveLyrics(track, it) }
        found
    }
}
