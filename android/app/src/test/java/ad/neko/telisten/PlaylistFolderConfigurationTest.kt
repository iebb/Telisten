package ad.neko.telisten

import ad.neko.telisten.data.PlaylistFolderConfiguration
import org.junit.Assert.*
import org.junit.Test

class PlaylistFolderConfigurationTest {
    @Test fun namesMatchAppleValidation() {
        assertEquals("_Playlist", PlaylistFolderConfiguration.DEFAULT_NAME)
        assertEquals("我的歌单", PlaylistFolderConfiguration.normalizedName("  我的歌单  "))
        assertEquals("Music 🎵", PlaylistFolderConfiguration.normalizedName("Music 🎵"))
        assertNotNull(PlaylistFolderConfiguration.normalizedName("123456789012"))
        listOf("", "   ", "1234567890123", "my\nplaylists", "my\tplaylists").forEach {
            assertNull(PlaylistFolderConfiguration.normalizedName(it))
        }
    }
}
