package ad.neko.telisten.player

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import ad.neko.telisten.data.TelegramRepository
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.drinkless.tdlib.TdApi as T
import java.io.IOException
import java.io.RandomAccessFile

/** ExoPlayer's loader thread reads the requested byte range from TDLib's seekable cache. */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class TelegramDataSource(private val repository: TelegramRepository) : BaseDataSource(true) {
    private var uri: Uri? = null
    private var fileId = 0
    private var position = 0L
    private var remaining = 0L
    private var opened = false
    @Volatile private var closed = false
    override fun getUri() = uri
    override fun open(dataSpec: DataSpec): Long {
        transferInitializing(dataSpec)
        uri = dataSpec.uri; closed = false; position = dataSpec.position
        try {
            val file = runBlocking { repository.call(T.GetRemoteFile(dataSpec.uri.getQueryParameter("remote") ?: error("Missing audio reference"), T.FileTypeAudio())) }
            fileId = file.id
            val size = file.size.takeIf { it > 0 } ?: file.expectedSize
            if (position > size) throw IOException("Seek outside audio file")
            remaining = if (dataSpec.length != C.LENGTH_UNSET.toLong()) minOf(dataSpec.length, size - position) else size - position
            runBlocking { repository.call(T.DownloadFile(fileId, 32, position, 0, false)) }
            opened = true; transferStarted(dataSpec)
            return remaining
        } catch (e: Exception) { throw IOException("Could not open Telegram audio", e) }
    }
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        try {
            return runBlocking {
                val deadline = System.nanoTime() + 60_000_000_000L
                while (!closed) {
                    val file = repository.call(T.GetFile(fileId))
                    val available = if (file.local.isDownloadingCompleted) file.size - position else
                        repository.call(T.GetFileDownloadedPrefixSize(fileId, position)).size
                    if (available > 0 && file.local.path.isNotEmpty()) {
                        val count = minOf(length.toLong(), remaining, available).toInt()
                        val read = RandomAccessFile(file.local.path, "r").use { it.seek(position); it.read(buffer, offset, count) }
                        if (read > 0) { position += read; remaining -= read; bytesTransferred(read); return@runBlocking read }
                    }
                    if (System.nanoTime() > deadline) throw IOException("Telegram audio timed out. Check your connection and retry.")
                    delay(80)
                }
                throw IOException("Stream closed")
            }
        } catch (e: Exception) { throw IOException("Could not read Telegram audio", e) }
    }
    override fun close() { closed = true; uri = null; if (opened) { opened = false; transferEnded() } }
    class Factory(private val repository: TelegramRepository) : DataSource.Factory { override fun createDataSource() = TelegramDataSource(repository) }
}
