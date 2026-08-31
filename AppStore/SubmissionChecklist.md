# Telisten submission checklist

Prepared for app record `6804541534`, bundle ID `ad.neko.player`, version `1.0.0`, build `26`.

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
- Build 26 is configured for both the iOS and macOS 1.0.0 versions; the shared Xcode Cloud workflows produce the signed archives after this revision is pushed.
- App pricing is free, with public availability in all supported countries and regions.
- Final iPhone, iPad, and Mac screenshot sets are uploaded and complete.

## Required before App Review

- Add a dedicated Telegram review account in App Review Sign-In Information. Do not place its code, password, or phone number in this repository.
- Add the App Review contact name, email address, and phone number.
- Complete the age-rating questionnaire based on the account/content available to review.
- Confirm third-party content rights and the content-rights declaration.
- Review and publish the App Privacy response. The implementation has no Kitta Co backend, advertising, or analytics; it communicates directly with Telegram and sends title, artist, and duration to LRCLIB for real-time matching.
- Complete each platform version submission.

## TestFlight access

- The internal `Admins` group contains three testers, all with Account Holder or Admin roles.
- No external testing group or public link exists.
- Distribute iOS and macOS build 26 only to the internal `Admins` group after processing completes.
- Keep the app record on Limited Access; Apple always grants Account Holder, Admin, Finance, and report roles their role-defined visibility.
