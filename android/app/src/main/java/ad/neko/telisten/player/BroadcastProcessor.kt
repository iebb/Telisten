package ad.neko.telisten.player

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import com.pedro.common.ConnectChecker
import com.pedro.rtmp.rtmp.RtmpClient
import kotlinx.coroutines.flow.MutableStateFlow
import java.nio.ByteBuffer
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Executors

/** A tee of app audio only. No microphone permission or device audio capture. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class BroadcastProcessor : BaseAudioProcessor() {
    val status = MutableStateFlow("idle")
    private val executor = Executors.newSingleThreadExecutor()
    private val pending = ArrayBlockingQueue<ByteArray>(64)
    @Volatile private var broadcasting = false
    @Volatile private var sampleRate = 44100
    @Volatile private var channels = 2
    private var client: RtmpClient? = null
    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        sampleRate = inputAudioFormat.sampleRate; channels = inputAudioFormat.channelCount
        return inputAudioFormat
    }
    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return
        if (broadcasting) {
            val copy = ByteArray(inputBuffer.remaining()); inputBuffer.duplicate().get(copy)
            if (!pending.offer(copy)) { status.value = "Broadcast could not keep up. Stop and retry."; broadcasting = false }
        }
        val output = replaceOutputBuffer(inputBuffer.remaining()); output.put(inputBuffer); output.flip()
    }
    fun start(url: String) {
        check(!broadcasting) { "Already broadcasting" }
        require(url.startsWith("rtmps://", ignoreCase = true)) { "Telegram must provide a secure RTMPS endpoint for broadcasting." }
        pending.clear(); broadcasting = true; status.value = "Connecting broadcast…"
        executor.execute {
            var encoder: MediaCodec? = null
            try {
                val rate = sampleRate; val count = channels
                val rtmp = RtmpClient(object : ConnectChecker {
                    override fun onConnectionStarted(url: String) { status.value = "Connecting broadcast…" }
                    override fun onConnectionSuccess() { status.value = "Live" }
                    override fun onConnectionFailed(reason: String) { status.value = "Broadcast connection failed"; broadcasting = false }
                    override fun onDisconnect() { if (broadcasting) { status.value = "Broadcast disconnected"; broadcasting = false } }
                    override fun onAuthError() { status.value = "Telegram rejected the broadcast"; broadcasting = false }
                    override fun onAuthSuccess() = Unit
                    override fun onNewBitrate(bitrate: Long) = Unit
                }).apply { setLogs(false); setOnlyAudio(true); setAudioInfo(rate, count == 2); connect(url) }
                client = rtmp
                encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                encoder.configure(MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, count).apply {
                    setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                    setInteger(MediaFormat.KEY_BIT_RATE, 128000)
                    setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
                }, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoder.start()
                val info = MediaCodec.BufferInfo(); var frames = 0L
                while (broadcasting) {
                    check(rate == sampleRate && count == channels) { "Audio format changed. Restart Listen Together for this track." }
                    val bytes = pending.poll(50, java.util.concurrent.TimeUnit.MILLISECONDS)
                    if (bytes != null) {
                        var offset = 0
                        while (offset < bytes.size && broadcasting) {
                            val input = encoder.dequeueInputBuffer(10_000)
                            if (input >= 0) {
                                val buffer = encoder.getInputBuffer(input)!!; buffer.clear()
                                val length = minOf(buffer.remaining(), bytes.size - offset)
                                buffer.put(bytes, offset, length)
                                encoder.queueInputBuffer(input, 0, length, frames * 1_000_000 / rate, 0)
                                frames += length / (count * 2); offset += length
                            }
                            drain(encoder, info, rtmp)
                        }
                    }
                    drain(encoder, info, rtmp)
                }
            } catch (e: Exception) { status.value = e.message ?: "Broadcast stopped"; broadcasting = false }
            finally { runCatching { encoder?.stop() }; encoder?.release(); client?.disconnect(); client = null; pending.clear() }
        }
    }
    private fun drain(encoder: MediaCodec, info: MediaCodec.BufferInfo, rtmp: RtmpClient) {
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, 0)
            if (index < 0) break
            val buffer = encoder.getOutputBuffer(index)
            if (buffer != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) rtmp.sendAudio(buffer, info)
            encoder.releaseOutputBuffer(index, false)
        }
    }
    fun stop() { broadcasting = false; status.value = "idle" }
    fun release() { stop(); executor.shutdown() }
}
