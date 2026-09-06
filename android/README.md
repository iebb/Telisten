# Telisten for Android

The Kotlin/Compose app in the [Telisten repository](../README.md). Uses Material 3, Media3, and TDLib. Requires Android 8.0 or newer; package ID: `ad.neko.player`.

## Build and run

Use JDK 17 and Android SDK 36. Open this directory in Android Studio, or run from the repository root:

```sh
cd android
./scripts/setup-tdlib.sh
./gradlew :app:assembleDebug
./gradlew :app:installDebug
```

Configure the SDK using `ANDROID_HOME` or `local.properties`. The build reads `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` from environment variables or the ignored root `.env`. Without credentials, **Explore demo** still works.

The APK is `app/build/outputs/apk/debug/app-debug.apk`. The Gradle wrapper and TDLib download are version- and checksum-pinned; do not commit downloaded binaries or local configuration.

## Tests

```sh
./gradlew :app:assembleDebug :app:assembleRelease :app:testDebugUnitTest :app:lintDebug
python3 scripts/smoke-test.py --serial emulator-5554 --adb "$ANDROID_HOME/platform-tools/adb"
```

Install the debug APK before running the smoke test. It uses demo data on a disposable emulator and checks navigation, playback, seeking, background controls, queue editing, downloads, and settings. It refuses physical devices.

Downloads survive ordinary backgrounding, but process termination may require retrying. Listen Together and less common authentication flows need further testing with real accounts.

## CI builds

**Actions → Android APKs** builds, tests, lints, and uploads debug/release APKs with checksums. It runs on Android changes to `master`, pull requests, `android-v*` tags, or manual dispatch. Artifacts are retained for 14 days; no store publishing is automatic.

Trusted builds use GitHub secrets for Telegram credentials and release signing. See [SECURITY.md](../SECURITY.md) for the secret names. PR builds never receive them. Without a configured signing key, release APKs are explicitly labeled **test-signed** and cannot provide a stable update signature.

To package locally after building, set `JAVA_HOME`, `ANDROID_HOME`, and the signing environment variables, then run `./scripts/package-apks.sh`. Output goes to ignored `dist/`. Play Store assets are in `play/`; `./gradlew :app:bundleRelease` builds an unsigned App Bundle.

## License

[BSD 3-Clause](../LICENSE) for Telisten. TDLib uses the Boost Software License; AndroidX, Kotlin, RootEncoder, and other dependencies retain their upstream licenses and notices.
