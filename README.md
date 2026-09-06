# Telisten

A native Telegram music player for iOS, macOS, and Android. Play music from your chats, organize playlists, and keep downloads and lyrics available offline. No Telisten server or bot token required.

## Features

- Music search across chats and through configurable search bots
- Streaming, downloads, a configurable cache, and background playback
- Telegram-backed playlists with a customizable folder name and local ordering
- Timed lyrics, alternative matches, LRC attachments, and offline lyrics caching
- Multiple accounts, favorites, queue controls, and Listen Together

Telegram permissions still apply. Secret chats are not supported. Listen Together is experimental.

## Build

Both apps live here: `Telisten/` contains the SwiftUI iOS/macOS app; [`android/`](android/README.md) contains the Kotlin/Compose Android app. Apple uses Swift MTProto libraries; Android uses TDLib and Media3.

Get a Telegram API ID and hash from [my.telegram.org](https://my.telegram.org), then create your local configuration:

```sh
cp .env.example .env
# Set TELEGRAM_API_ID and TELEGRAM_API_HASH in .env.
```

### iOS and macOS

Use Xcode 26.6 (Swift 6.3), with iOS 18+ or macOS 15+ as the deployment target.

```sh
./Scripts/generate-local-config.sh
open Telisten.xcodeproj
```

Select `Telisten-iOS` or `Telisten-macOS`, choose your signing team, and run. Review and trust the pinned `TLCodingMacros` macro if prompted. Add `--demo` to a Debug scheme to explore without logging in. XcodeGen is only needed when changing `project.yml`.

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
