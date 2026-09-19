# Embedded lyrics fixtures

These are 0.1-second silent audio files generated with FFmpeg, containing only
the synthetic LRC lines `Embedded first line` (0 seconds) and `Embedded next line`
(0.05 seconds). No third-party recordings or lyrics are included.

Formats: MP3 ID3 TXXX/USLT, M4A lyrics atom, and FLAC Vorbis `LYRICS` comment.
Run `bash Scripts/test-offline-lyrics.sh` to test extraction and offline priority.
