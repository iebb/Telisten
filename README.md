# Telisten

A native Telegram music player for iOS, macOS, visionOS, and Android. Play music from your chats, organize playlists, and keep downloads and lyrics available offline. No Telisten server or bot token required.

## Features

- Music search across chats and through configurable search bots
- Streaming, downloads, a configurable cache, and background playback
- Telegram-backed playlists with a customizable folder name and local ordering
- Timed lyrics, alternative matches, LRC attachments, and offline lyrics caching
- Floating lyrics windows on macOS and visionOS, with an optional always-on-top mode on Mac
- Multiple accounts, favorites, queue controls, and Listen Together

Telegram permissions still apply. Secret chats are not supported. Listen Together is experimental.

## Build

Both apps live here: `Telisten/` contains the SwiftUI iOS/macOS/visionOS app; [`android/`](android/README.md) contains the Kotlin/Compose Android app. Apple uses Swift MTProto libraries; Android uses TDLib and Media3.

Get a Telegram API ID and hash from [my.telegram.org](https://my.telegram.org), then create your local configuration:

```sh
cp .env.example .env
# Set TELEGRAM_API_ID and TELEGRAM_API_HASH in .env.
```

### iOS, macOS, and visionOS

Use Xcode 26.6 (Swift 6.3), with iOS 18+, macOS 15+, or visionOS 2+ as the deployment target.

```sh
./Scripts/generate-local-config.sh
open Telisten.xcodeproj
```

Select `Telisten-iOS`, `Telisten-macOS`, or `Telisten-visionOS`, choose your signing team, and run. Review and trust the pinned `TLCodingMacros` macro if prompted. Add `--demo` to a Debug scheme to explore without logging in. XcodeGen is only needed when changing `project.yml`.

On visionOS, choose the Apple Vision Pro destination and install the visionOS SDK/simulator in Xcode if needed. The native app opens a resizable library window with a separate lyrics window you can place in your space. Use `--demo --demo-chat --demo-floating-lyrics` in a Debug scheme to preview both windows without signing in.

#### Floating lyrics

On Mac or Apple Vision Pro, select **Floating Lyrics** (the overlapping windows button) in the player bar or Now Playing. The compact, borderless overlay shows the current and next line, with a transparent background by default. Select a timed line to seek; untimed lyrics have manual paging controls. Opening it again brings the existing window forward. Closing it leaves playback running.

The Mac title and control bar appears only while hovering over the lyrics window and hides when the pointer leaves, without shifting the lyrics. Hover to reveal playback controls, the drag grip, lyric matches, and **Customize Lyrics**. Drag the grip or empty background to move the window. On visionOS the controls stay visible; use the system window bar to reposition the lyrics in your space. Customize single/double lines, alignment, width, font style and size, bold text, outline, current/next colors, text/background opacity, and the optional song title. Color presets and **Reset Appearance** are included; changes persist across launches.

On Mac, **Center Horizontally on Current Screen** in the floating toolbar centers the window on the display it currently occupies without changing its vertical position. **Playback → Floating Lyrics** (⇧⌘L) also opens or unlocks the overlay. **Keep on Top** is enabled by default. The lock button makes the window ignore mouse clicks so you can work through it; reopen Floating Lyrics or use **Playback → Lock Floating Lyrics** to unlock. The existing in-library Lyrics view (⌘L) is still available.

### Android

Use JDK 17 and Android SDK 36. Configure the SDK through Android Studio, `ANDROID_HOME`, or `android/local.properties`.

```sh
cd android
./scripts/setup-tdlib.sh
./gradlew :app:assembleDebug
```

See the [Android README](android/README.md) for installation and tests.

## CI and credentials

GitHub Actions builds both platforms on `master`, tests the offline library, and scans source/history for secrets. Set repository secrets `TELEGRAM_API_ID` and `TELEGRAM_API_HASH`; pull requests receive neither. Xcode Cloud uses its own secret environment variables. See [SECURITY.md](SECURITY.md) for signing secrets and credential handling.

Never commit `.env`, session data, publishing credentials, or signing keys. Native binaries contain the Telegram application ID/hash; keeping them in CI secrets protects source, not distributed binaries.

## License

[BSD 3-Clause](LICENSE). Third-party dependencies retain their own licenses. Store screenshots and demo song references do not grant rights to the referenced music or lyrics.
