package ad.neko.telisten.data

object PlaylistFolderConfiguration {
    const val DEFAULT_NAME = "_Playlist"

    fun normalizedName(raw: String): String? {
        val value = raw.trim()
        return value.takeIf {
            it.isNotEmpty() && it.codePointCount(0, it.length) <= 12 && it.none(Char::isISOControl)
        }
    }
}
