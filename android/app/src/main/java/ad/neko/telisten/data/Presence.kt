package ad.neko.telisten.data

/** Wire format shared with the Swift client, carried in the Telegram call title. */
data class Presence(val title: String, val artist: String, val elapsed: Long, val duration: Long, val playing: Boolean) {
    fun encode(): String {
        val prefix = if (playing) "♫ " else "Ⅱ "
        val suffix = " · ${timeLabel(elapsed)}/${timeLabel(duration)}"
        val identity = if (artist.isEmpty()) title else "$title — $artist"
        return prefix + identity.take((64 - prefix.length - suffix.length).coerceAtLeast(1)) + suffix
    }
    companion object {
        fun parse(value: String): Presence? {
            if (!value.startsWith("♫ ") && !value.startsWith("Ⅱ ")) return null
            val match = Regex("^(?:♫|Ⅱ) (.+) · (\\d+):(\\d{2})/(\\d+):(\\d{2})$").matchEntire(value) ?: return null
            val identity = match.groupValues[1].split(" — ", limit = 2)
            return Presence(identity[0], identity.getOrElse(1) { "" }, match.groupValues[2].toLong() * 60 + match.groupValues[3].toLong(), match.groupValues[4].toLong() * 60 + match.groupValues[5].toLong(), value.startsWith("♫"))
        }
    }
}
