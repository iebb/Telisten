# Telisten for Android

Native Kotlin / Jetpack Compose Android app, using compact Material 3 Expressive controls and Media3. Version 1.1 puts songs first, with separate Songs/Playlists/Chats tabs, 64 dp song rows, direct favorite controls, and a player with a small artwork thumbnail and persistent transport controls above lyrics, queue, and comments. This Android Studio project lives alongside the Apple app in the same `iebb/Telisten` repository.

## Build and run

Requirements: JDK 17, Android SDK 36, and Android 8.0 / API 26 or newer on the device.

```sh
cd android
# Use JDK 17 (newer JDKs such as 26 are not compatible with this Gradle setup).
./scripts/setup-tdlib.sh
# Configure the SDK through Android Studio, ANDROID_HOME, or local.properties.
./gradlew :app:assembleDebug
./gradlew :app:installDebug
```

Open this directory in Android Studio. The checked-in Gradle wrapper downloads its pinned, checksum-verified distribution. The setup script downloads the pinned TDLib Android AAR and checks its SHA-256 before installing it into the ignored `app/libs/` directory. Do not commit the AAR, local properties, signing keys, or credentials.

The Android build reads `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` from the repository's existing `../.env`, or from environment variables (which take precedence). Obtain these from [my.telegram.org](https://my.telegram.org). Missing credentials do not prevent building or exploring the interface; the login screen explains what to configure. Like any native Telegram client, the built APK contains the app API credentials.

Debug APK: `app/build/outputs/apk/debug/app-debug.apk`.

```sh
# Inspect the interface without authorizing a Telegram account:
adb shell am start -n ad.neko.player/ad.neko.telisten.MainActivity --ez demo true
```

The login screen also offers **Explore demo**. Fixtures are explicitly labeled and do not send Telegram messages, reactions, or playlist mutations. Demo playback uses a locally generated, quiet 30-second tone; the track names and lyrics are fictional. Demo favorites, downloads, and playlists are in-memory previews.

## GitHub Actions: downloadable APKs

The workflow is `.github/workflows/android-apks.yml`. **Actions → Android APKs** runs for Android changes on `master`, pull requests, `android-v*` tags, or **Run workflow**. Credentials are supplied only on `master` and Android release tags, never pull requests or manual builds of other branches.

Each run installs Java 17 / Android SDK 36, validates the Gradle wrapper, downloads checksum-verified TDLib, builds debug and minified release APKs, runs unit tests and lint, signs/verifies the APKs, and uploads:

- `telisten-apks-<run>-<commit>`: debug APK, installable release APK, `SHA256SUMS`, and signing notes. Artifacts are retained for 14 days.
- `android-reports-<run>`: lint and test reports, including on failed builds.

Add repository **Actions secrets** for working Telegram sign-in in builds from pushes/manual runs:

| Secret | Value |
| --- | --- |
| `TELEGRAM_API_ID` | Your Telegram application ID |
| `TELEGRAM_API_HASH` | Your Telegram application hash |

Without those credentials, APKs still build and support the demo/offline interface; sign-in explains that a rebuild with credentials is required. Pull-request builds never receive credentials or signing secrets, including PRs from this repository.

For a consistent release signing identity, configure all four optional secrets together:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded signing keystore (whitespace is accepted) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Signing alias |
| `ANDROID_KEY_PASSWORD` | Alias password |

With these secrets the release artifact is `telisten-release.apk`. Otherwise it is explicitly named `telisten-release-test-signed.apk`, signed using the runner's debug key. CI test keys are ephemeral: use the same configured release key to install updates across runs. Gradle's debug APK keeps its separate debug signing identity. Both builds use `ad.neko.player`, so differing signatures cannot update one another.

CI version codes are `1000 + github.run_number`; local builds use version code 3. Signing keystores are decoded only into a temporary directory and removed after packaging. Workflow actions are pinned to commit hashes; permissions are read-only. This workflow uploads build artifacts, not GitHub Releases or Play Store submissions.

To produce the same APK bundle locally:

```sh
cd android
# Set JAVA_HOME to your JDK 17 directory and ANDROID_HOME to your Android SDK.
./gradlew :app:assembleDebug :app:assembleRelease :app:testDebugUnitTest :app:lintDebug
./scripts/package-apks.sh
```

## Google Play submission

The initial Kitta submission uses package `ad.neko.player`, version `1.1.0` (code `3`). The prepared, signed App Bundle is `dist/telisten-1.1.0-play.aab`; `dist/PLAY-SHA256SUMS` records its checksum and `dist/telisten-upload-certificate.pem` contains its public upload certificate. Build the unsigned bundle with Java 17 and `./gradlew :app:bundleRelease` before signing future versions.

The service-account credential is the repository-root `.play_account.json`, explicitly excluded by the root `.gitignore`. The dedicated upload keystore and password configuration are stored in the ignored `.local/android-publishing/` directory at the repository root, with restricted filesystem permissions. Keep a secure backup of that directory and reuse this upload key for later Play submissions. The service-account credential authenticates the publishing API; it does not sign the app.

On September 6, 2026, the signed version-code-3 production release and all 11 associated changes were submitted through the Kitta Play Console. Console shows “Changes in review”; automated pre-review checks were still running at the last verification. Availability targets all 177 country/region entries, including Rest of World. Managed publishing is off, so an approved release publishes automatically. The English listing, icon, feature graphic, five phone screenshots, privacy policy, review sign-in instructions, target audience, data safety declarations, and IARC rating are included. IARC rates it Everyone / PEGI 3 in most regions and USK 16 in Germany, with Users Interact disclosed; the chosen target audience remains adults 18+. Release validation has no blocking errors and one advisory about missing native debug symbols for prebuilt libraries; the ReTrace mapping file is attached. Store assets live in `play/`; reviewer credentials are kept out of this repository. The existing APK workflow does not automatically publish to Play.

## Feature mapping

| Existing feature | Android implementation |
| --- | --- |
| Phone, code, email, password, QR login | TDLib authorization-state flow, including rotating Telegram QR links |
| Multiple accounts | Separate encrypted TDLib databases and libraries; database keys wrapped by Android Keystore |
| Cloud chats and saved chats | Main and archived chats, searchable chat picker, local bookmarks; secret chats excluded |
| Music search and pagination | Audio-filtered chat/global searches with Telegram cursors |
| Playback | Seekable Telegram byte-range data source; Media3 queue, previous/next, shuffle, order, reverse, repeat one |
| Background audio | Foreground media playback service, audio focus, headphone-disconnect handling, media notification and system controls |
| Favorites and downloads | Persistent per-account library, explicit downloads, progress, removal, playlist download-all |
| Cache | Configurable default 2 GB budget, atomic download commits, LRU eviction and TDLib stream-cache optimization |
| Lyrics | Cached synchronized/plain LRCLIB lyrics, HTTPS server setting, alternative matches, matching Telegram LRC documents, document-picker imports |
| Votes and comments | Real Telegram thumbs-up reactions and threaded replies, including linked channel discussions |
| Playlists | Private broadcast channels in a configurable per-account folder (default `_Playlist`); preserves existing folder fields; create/save/rename/delete/remove songs; local ordering |
| Bot search | Configurable username/prefix/suffix, persistent ordering, conversation polling, audio results, inline callbacks, reply keyboards, links |
| Listen Together | Telegram RTMP hosting of app audio, invites/contact picker; Swift-compatible title metadata and matching-track listener synchronization |
| Design | MaterialExpressiveTheme, standard sans-serif typography, compact toolbar and rows, 48 dp touch targets, separate collection tabs, persistent player controls, light/dark themes |

TDLib is used only in the Android app, replacing the Apple app's Swift MTProto libraries. Both connect directly to Telegram; there is no Telisten backend or bot token. Native Java bindings and all four ABI binaries come from [tdlib-android v0.1.0](https://github.com/AkashPriyadarshii/tdlib-android/releases/tag/v0.1.0). RTMP transport uses [RootEncoder 2.6.4](https://github.com/pedroSG94/RootEncoder/tree/2.6.4).

## Behavior and boundaries

- Telegram controls permissions, protected-message forwarding, reactions, channel creation, comments, and who can host a call. The app surfaces server errors and failed message sends.
- Comments, bot searches, playlist saves, and invitations are real Telegram actions triggered by their labeled UI controls. Deletion and sign-out have confirmation dialogs.
- Offline files and favorites remain in their account's library after sign-out. Signing in again or switching accounts never shares authorization keys between accounts. Android cloud backup and device transfer are disabled for app data.
- The cache budget reserves up to 256 MB (at most one quarter of the total) for Telegram streaming; the rest is for explicit downloads. Active transfers, recently accessed stream files, and the protected current download can temporarily exceed the budget. The metadata database and lyrics are outside the audio budget. A single download must fit the download portion.
- Downloads are owned by the activity's ViewModel, not a WorkManager transfer service. They survive rotation and ordinary backgrounding; process termination requires retrying. Telegram's partial file cache permits safe resumption.
- Listen Together listeners use matching songs accessible to their own account, like the Swift client. The invite link allows listening to the actual hosted stream in Telegram when a song is unavailable locally. Hosting broadcasts only the app's decoded audio, never the microphone. If the source sample rate/channel layout changes, stop and restart hosting; this version reports that format change rather than silently sending incorrectly encoded audio.
- Gradle produces an unsigned release APK. `./scripts/package-apks.sh` signs it using a configured keystore or the local test key, verifies signatures/alignment, and writes both installable APKs plus checksums to `dist/`. Nothing is published to an app store.

## Verification

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:assembleRelease
python3 scripts/smoke-test.py --serial emulator-5554 --adb "$ANDROID_HOME/platform-tools/adb"
```

The smoke script is for a disposable emulator with the debug APK installed. It refuses physical devices, stops/relaunches Telisten in demo mode on the emulator, verifies six songs fit on the first screen, tests direct favorites, collection tabs, search/clear, actual Media3 playback and seeking, background system media keys, queue reordering, downloads, and settings. It never signs in. Screenshots are saved in `screenshots/`.

Verified locally on an Android 14 / API 34 ARM64 emulator:

- Debug APK and R8-minified release APK build successfully.
- Android lint passes with no errors; remaining warnings are dependency update suggestions and style/platform advisories.
- Nine unit tests pass: LRC metadata, offsets, multiple timestamp tags, precision, plain text; Swift-compatible presence parsing/limits; bot formatting; audio-processor empty-buffer regression and PCM transparency.
- Device smoke checks cover the compact library, favorites, collection tabs, search, playback progress, repeat-one, background media controls, seek, queue reordering, downloads, and settings.
- Native TDLib phone/code sign-in succeeded with the supplied review account; the protected code page was opened in Safari. Light/dark screenshots were inspected. Store screenshots use labeled demo data at 1080 × 1920.
- Version-code-3 release APK was installed as an update on the connected Nothing A142, preserving app data.
- The APK ZIP alignment and ARM64/x86-64 TDLib ELF segments meet 16 KB alignment requirements.

Email/2FA authorization, Telegram range playback and mutations, two-account switching, and end-to-end RTMPS hosting/listening have **not** been exercised against a signed-in account. They use actual TDLib/RTMP implementations, not successful placeholder responses. Validate these with test accounts and a private test channel before distributing the app.

## Source layout

- `data/TelegramRepository.kt`: typed asynchronous Telegram operations and updates.
- `data/LibraryStore.kt`: account-local library, cache, and Keystore-wrapped database keys.
- `data/LyricsRepository.kt`, `data/Presence.kt`: lyrics and cross-platform synchronization format.
- `player/`: Media3 service, Telegram range reads, PCM tee/AAC/RTMP broadcast.
- `ui/`: application state, Material 3 Expressive theme, library/player/login/settings/bot/session screens.

## Dependency licenses

TDLib: Boost Software License 1.0. The Android packaging project: Boost / Apache 2.0 as documented upstream. AndroidX, Kotlin, OkHttp, Coil, ZXing, and RootEncoder: Apache 2.0. See each dependency's upstream license and bundled notices when distributing the app.
