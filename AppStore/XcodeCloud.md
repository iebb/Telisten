# Xcode Cloud release workflow

App Store Connect contains one enabled workflow named `Default` for `Telisten.xcodeproj`.

## Start condition

- Repository: `iebb/Telisten`
- Branch: exact match `master`
- Automatically cancel superseded builds: enabled

## Archive actions

1. `Archive - iOS`: scheme `Telisten-iOS`, platform iOS, App Store-eligible archive
2. `Archive - macOS`: scheme `Telisten-macOS`, destination Any Mac, App Store-eligible archive

## Required secret environment variables

Add these two workflow environment variables in App Store Connect and mark both **Secret**:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`

`ci_scripts/ci_post_clone.sh` passes them to `Scripts/generate-local-config.sh`, which writes the ignored `.local/Telegram.xcconfig`. Never put either value in a tracked file.

The post-clone script also enables Xcode's noninteractive macro validation bypass for `TLCodingMacros`, the sole compiler macro and one pinned by `Package.resolved`. Local developers should continue reviewing and explicitly trusting the package in Xcode.

## TestFlight

Distribute only through the internal `Admins` group. Do not create an external group or public link for Telisten. Apple requires Xcode Cloud builds to be added to the internal group after the build finishes processing; the group must contain only eligible App Store Connect users with the Account Holder or Admin role.
