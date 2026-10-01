# Xcode Cloud release workflow

App Store Connect has an enabled `Default` workflow for `Telisten.xcodeproj`. It runs on changes to `master` and automatically cancels superseded builds.

## Archive actions

| Platform | Scheme | Distribution preparation |
| --- | --- | --- |
| iOS | `Telisten-iOS` | App Store Connect |
| macOS | `Telisten-macOS` (Any Mac) | App Store Connect |
| visionOS | `Telisten-visionOS` | App Store Connect |

Each platform has its own target and shared archive scheme. The visionOS app record uses the existing `ad.neko.player` bundle ID in App Store Connect.

## TestFlight post-actions

- iOS and macOS archives go to the existing `Internal` and `External` groups.
- visionOS archives go to the existing `Internal` group for initial validation. Add an external post-action after a visionOS build has passed testing and its external TestFlight requirements are ready.

Xcode Cloud uploads an archive after its archive action succeeds. App Store Connect processes the build before it becomes available in TestFlight. Check the build and post-action status in Xcode Cloud after pushing to `master`.

## Build environment

The workflow uses the latest release of Xcode and macOS. It supplies `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` through shared workflow environment variables. `ci_scripts/ci_post_clone.sh` passes them to `Scripts/generate-local-config.sh`, which writes the ignored `.local/Telegram.xcconfig`. Do not put either value in a tracked file.

The post-clone script also enables Xcode's noninteractive macro validation bypass for the pinned `TLCodingMacros` package. Local developers should continue reviewing and explicitly trusting the package in Xcode.
