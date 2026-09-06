# Telisten

Telisten is a native Telegram music player for iPhone, iPad, Mac, and Android. It signs in as the user, finds audio in accessible cloud chats, and keeps downloaded tracks available offline. Both platform implementations live in this repository; there is no Telisten backend or bot token.

- **iOS and macOS:** SwiftUI app in `Telisten/`, with `Telisten.xcodeproj` at the repository root. Uses Swift MTProto libraries, not TDLib.
- **Android:** Kotlin/Compose app in [`android/`](android/README.md), with its own Gradle project. The Android implementation uses TDLib and Media3.
- **CI:** GitHub Actions builds both implementations on `master`; Xcode Cloud handles Apple distribution. See [credential handling and publication checks](SECURITY.md).

## Features

- Phone-number sign-in, Telegram or email login codes, login-email setup, and two-step verification
- Browse every accessible cloud chat, search music in one chat or across Telegram, and lazily load long music histories
- Queue playback in shuffle, order, reverse-order, or repeat-one mode; seek, previous/next, favorites, and a full now-playing view
- Synchronized or plain lyrics from LRCLIB or a configured LRCLIB-compatible server, cached locally with source attribution
- Telegram-backed 👍 votes, including shared counts and optimistic UI updates
- “Save to playlist” using private Telegram channels collected in a configurable folder (default `_Playlist`)
- Lock-screen/Control Center media controls and background audio on iOS
- Seekable MTProto streaming for quick playback, plus explicit downloads with progress and a bounded 2 GB least-recently-used cache
- Offline Downloads and Favorites libraries
- Gitignored local Telegram app configuration; MTProto authorization keys stay in Keychain
- Native SwiftUI interface shared by iOS and macOS

“Any chat” means any Telegram cloud chat the signed-in account can access. Telegram secret chats are device-specific, end-to-end encrypted sessions and are not exposed to a newly authorized API client.

## Run the Apple app

Requirements:

- Xcode 26 or newer
- iOS 18+ or macOS 15+
- A Telegram `api_id` and `api_hash` from [my.telegram.org](https://my.telegram.org)

Keep the credentials in the local `.env`; they are never written into tracked Swift or project files:

```sh
cp .env.example .env
# Fill in TELEGRAM_API_ID and TELEGRAM_API_HASH, then:
./Scripts/generate-local-config.sh
xcodegen generate
```

The script creates `.local/Telegram.xcconfig`, which is also gitignored. Xcode expands those values into the built app's Info.plist. Like every native Telegram client credential, they can still be extracted from the compiled app, so this protects the repository rather than treating the API hash as a user password.

Open `Telisten.xcodeproj`, select either `Telisten-iOS` or `Telisten-macOS`, and run. Xcode may ask you to trust the `TLCodingMacros` package macro the first time; review and enable it.

### Xcode Cloud

The repository includes `ci_scripts/ci_post_clone.sh` for Xcode Cloud. Configure one workflow from pushes to `master` with two archive actions: `Telisten-iOS` for iOS and `Telisten-macOS` for macOS. Distribute successful archives only to the admins-only internal TestFlight group. Add `TELEGRAM_API_ID` plus `TELEGRAM_API_HASH` as secret environment variables; the hook generates the ignored `.local/Telegram.xcconfig` before Xcode builds.

The App Store copy, review notes, submission checklist, and verified screenshot output folders live in `AppStore`.

### GitHub Actions

`Apple builds` verifies iOS Simulator and macOS builds plus the offline-library tests. `Android APKs` builds, tests, lints, and packages Android APKs. `Secret scan` checks the full reachable Git history and current source using checksum-pinned Gitleaks. Actions are pinned to commit hashes and use read-only repository permissions.

Configure repository Actions secrets `TELEGRAM_API_ID` and `TELEGRAM_API_HASH`; both platform workflows consume them for trusted builds only. Pull requests build without application credentials or signing keys. Android release-signing secret names and artifact details are documented in [`android/README.md`](android/README.md). Neither workflow publishes to an app store. Xcode Cloud has a separate secret store and still needs its own secret environment variables.

To inspect the complete interface without Telegram credentials, add the `--demo` launch argument to a Debug scheme. The fixture never writes to Telegram; it provides sample chats, votes, a playlist, and a current track so the LRCLIB and playlist interfaces can be exercised in Simulator.

For an unsigned command-line verification build:

```sh
xcodebuild -project Telisten.xcodeproj \
  -scheme Telisten-macOS \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation build

xcodebuild -project Telisten.xcodeproj \
  -scheme Telisten-iOS \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  -skipMacroValidation build
```

Do not install those unsigned artifacts in Simulator. Use Xcode Run, or omit `CODE_SIGNING_ALLOWED=NO`, so iOS can retain the MTProto authorization key in Keychain across launches.

On first launch, sign in with your phone number. Telegram may deliver the code in Telegram, by email, or through another method selected by the service. Telisten also handles mandatory login-email setup and two-step verification.

## Small by design

The handwritten application is split into four narrow layers:

- `TelegramService`: direct MTProto connection, authentication, chat search, and file transfer
- `CacheStore`: atomic local files, metadata, and LRU eviction
- `AudioPlayer`: AVPlayer, media keys, and now-playing metadata
- `AppModel` and `Views`: queue/library state and adaptive SwiftUI screens

The full Telegram schema is intentionally not checked in. `Generated/TelegramAPI` contains only the 45 RPC methods the player uses and their transitively required types.

Dependencies are pinned through Swift Package Manager:

- [`swift-mtproto`](https://github.com/UInt8Co/swift-mtproto) for TL coding, schema generation, cryptography, and SRP primitives
- [`swift-nio-mtproto`](https://github.com/UInt8Co/swift-nio-mtproto) for the encrypted MTProto transport

Both packages are small Swift building blocks rather than TDLib or a complete Telegram client.

## Regenerate the Telegram API subset

The checked-in sources target Telegram schema layer 223. When Telegram changes the schema, run:

```sh
./Scripts/regenerate-telegram-api.sh
./Scripts/generate-local-config.sh
xcodegen generate
```

The script downloads Telegram's official live schema and schema index, checks that the published layer matches `TelegramService`, and generates only the methods listed in `telegram-methods.txt`. It requires `curl`, `git`, and Swift 6.3+; `xcodegen` is only needed to recreate the project after changing file layout or `project.yml`.

## Operational notes

- Audio is streamed in byte ranges directly from Telegram data centers. The Download action stores the complete track for offline playback; there is no Telisten server.
- Lyrics queries send the track title, artist, and duration to the LRCLIB-compatible server selected in Settings (the default is [LRCLIB](https://lrclib.net)); successful matches are cached on-device. For a commercial release that requires publisher-cleared coverage or service guarantees, replace `LRCLIBProvider` with a licensed provider such as Musixmatch.
- A vote is a real 👍 Telegram message reaction. Comments are Telegram replies; channel-post comments are sent through the linked discussion. Saving forwards the original audio message, so Telegram's forwarding permissions still apply.
- New playlists are private broadcast channels. Telisten creates or updates the `_Playlist` dialog folder without changing unrelated folders or their settings.
- The app asks Telegram not to redirect file transfers to its CDN, keeping the transfer code compact. A download reports a clear error if Telegram still returns a CDN redirect.
- Cached files are stored in the platform Caches directory and may be removed from the Downloads screen. The cache automatically evicts least-recently-used files above 2 GB.
- Playback can continue in the background. A download in progress is foreground-bound on iOS; restarting it is safe because cache commits are atomic.
- Distribution builds use the `ad.neko.player` bundle identifier. Review Telegram's [API terms](https://core.telegram.org/api/terms) and Apple distribution requirements before release.

## Reference

The implementation follows Telegram's official documentation for [API credentials](https://core.telegram.org/api/obtaining_api_id), [user authorization](https://core.telegram.org/api/auth), [message search](https://core.telegram.org/api/search), [file downloads](https://core.telegram.org/api/files), [dialog folders](https://core.telegram.org/api/folders), [message reactions](https://core.telegram.org/method/messages.sendReaction), [discussion threads](https://core.telegram.org/api/discussion), [replying](https://core.telegram.org/method/messages.sendMessage), [forwarding](https://core.telegram.org/method/messages.forwardMessages), [invite links](https://core.telegram.org/api/invites), and [group-call invitations](https://core.telegram.org/api/group-calls).
