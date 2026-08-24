# Telisten submission checklist

Prepared for app record `6804541534`, bundle ID `ad.neko.player`, version `1.0.0`, build `1`.

## Ready

- App name, subtitle, promotional text, description, keywords, URLs, release notes, and review notes are in `Metadata/en-US` and `Review`.
- Public privacy policy: https://docs.kitta.co/telisten/
- Public support page: https://docs.kitta.co/support/
- App Privacy implementation inventory: `AppPrivacyWorksheet.md`
- Shared iOS and macOS schemes are available to Xcode Cloud.
- Xcode Cloud generates the ignored Telegram configuration from secret workflow environment variables.
- The checked workflow specification and final secret-variable step are documented in `XcodeCloud.md`.
- The 6.9-inch iPhone and 13-inch iPad screenshot sets are checked in without alpha channels and uploaded to the iOS version.
- `ITSAppUsesNonExemptEncryption` is `false` in both platform Info.plists, and both uploaded builds have the same export-compliance declaration.
- Xcode Cloud run 4 passed both platform archives and both internal TestFlight distribution actions.

## Required before App Review

- Add a dedicated Telegram review account in App Review Sign-In Information. Do not place its code, password, or phone number in this repository.
- Complete the age-rating questionnaire based on the account/content available to review.
- Confirm third-party content rights and the content-rights declaration.
- Review and publish the App Privacy response. The implementation has no Kitta Co backend, advertising, or analytics; it communicates directly with Telegram and sends title, artist, and duration to LRCLIB for real-time matching.
- Choose price, tax category, and storefront availability.
- Capture and upload at least one 16:10 Mac screenshot with no alpha channel.
- Select the processed iOS and macOS builds, then complete each platform version submission.

## TestFlight access

- The internal `Admins` group contains three testers, all with Account Holder or Admin roles.
- No external testing group or public link exists.
- Keep the app record on Limited Access; Apple always grants Account Holder, Admin, Finance, and report roles their role-defined visibility.
