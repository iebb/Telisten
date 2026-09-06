package ad.neko.telisten

import ad.neko.telisten.player.BroadcastProcessor
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class BroadcastProcessorTest {
    @Test fun emptyPipelineSentinelDoesNotCopyBufferOntoItself() {
        val processor = BroadcastProcessor()
        processor.queueInput(AudioProcessor.EMPTY_BUFFER)
        assertFalse(processor.output.hasRemaining())
        processor.release()
    }
    @Test fun playbackPcmIsUnchangedWhenNotBroadcasting() {
        val processor = BroadcastProcessor()
        processor.configure(AudioProcessor.AudioFormat(44100, 2, C.ENCODING_PCM_16BIT))
        processor.flush()
        val source = byteArrayOf(1, 0, 2, 0, -1, 127, 0, -128)
        val input = ByteBuffer.allocateDirect(source.size).put(source).apply { flip() }
        processor.queueInput(input)
        assertFalse(input.hasRemaining())
        val actual = ByteArray(source.size)
        processor.output.get(actual)
        assertArrayEquals(source, actual)
        processor.release()
    }
}
