package ad.neko.telisten

import ad.neko.telisten.data.*
import org.junit.Assert.*
import org.junit.Test

class LyricsAndPresenceTest {
    @Test fun repeatedTimestampsAndOffsetStaySorted() {
        val lines = LrcParser.parse("[ar:Artist]\n[offset:-250]\n[00:10.5][00:02.250]Hello\n[00:04.00]World")
        assertEquals(listOf(2.0, 3.75, 10.25), lines.map { it.seconds })
        assertEquals(listOf("Hello", "World", "Hello"), lines.map { it.text })
    }
    @Test fun plainLyricsPreserveWordsWithoutMetadata() {
        val lines = LrcParser.parse("[ti:Title]\nFirst line\n\nSecond line")
        assertEquals(listOf("First line", "Second line"), lines.map { it.text })
        assertTrue(lines.all { it.seconds == null })
    }
    @Test fun centisecondsAndMillisecondsAreDifferent() {
        assertEquals(.12, LrcParser.parse("[00:00.12]a").single().seconds!!, .0001)
        assertEquals(.012, LrcParser.parse("[00:00.012]a").single().seconds!!, .0001)
    }
    @Test fun swiftPresenceWireFormatRoundTrips() {
        val presence = Presence("Warm light", "The Sunday Club", 72, 241, true)
        assertEquals("♫ Warm light — The Sunday Club · 1:12/4:01", presence.encode())
        assertEquals(presence, Presence.parse(presence.encode()))
        assertEquals(false, Presence.parse("Ⅱ Warm light — The Sunday Club · 1:12/4:01")?.playing)
    }
    @Test fun ordinaryCallTitlesDoNotTriggerPlayback() {
        assertNull(Presence.parse("Weekly catch-up"))
        assertNull(Presence.parse("♫ Music · bad/time"))
    }
    @Test fun longTitlesKeepTimingAndTelegramLimit() {
        val value = Presence("a".repeat(200), "Artist", 3601, 7200, false).encode()
        assertTrue(value.length <= 64)
        assertEquals(3601L, Presence.parse(value)?.elapsed)
        assertEquals(7200L, Presence.parse(value)?.duration)
    }
    @Test fun botSearchKeepsConfiguredWhitespaceAndTrimsQuery() {
        assertEquals("/search Ambient Music --audio", SearchBot("musicbot", "/search ", " --audio").command("  Ambient Music  "))
    }
}
