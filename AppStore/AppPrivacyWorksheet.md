# App Privacy worksheet

Use this worksheet when completing App Store Connect's App Privacy questionnaire. It describes the shipping implementation; the Account Holder should confirm the final declarations before publishing them.

## Kitta Ltd

Telisten has no Kitta account, backend, advertising, analytics, telemetry, crash-reporting SDK, or tracking SDK. Kitta Ltd does not receive music, chats, credentials, contacts, usage history, or diagnostic data from the app.

## Telegram

The user signs in to Telegram and asks Telisten to read or send data in that Telegram account. The app communicates directly with Telegram over MTProto. Depending on the feature used, Telegram receives or retains:

- phone number, Telegram user ID, and authorization-session information for sign-in;
- audio requests needed to search, stream, download, forward, and manage the `_Playlist` folder;
- forwarded audio, new private playlist channels, and folder changes that the user explicitly creates.

These operations are core app functionality, are linked to the user's Telegram account by Telegram, and are not used by Kitta Ltd for tracking or advertising. Review Telegram's current privacy practices before publishing the questionnaire because Apple requires third-party partner practices to be included.

## LRCLIB

When lyrics are requested, Telisten sends track title, artist, and duration to LRCLIB for a real-time match. It does not send the user's Telegram identity, chat ID, message ID, phone number, or audio file. The matched lyrics are cached locally. Confirm LRCLIB's current server-side retention practices before publishing the questionnaire.

## On-device data

Telegram authorization keys are stored in Keychain. Audio, artwork, chat music counts, queues, preferences, and lyrics are cached on-device. On-device-only processing and storage are not an App Privacy “collection” unless the data is transmitted off-device.

## Tracking

Telisten does not combine app data with third-party data for advertising, advertising measurement, or data-broker purposes, and does not access Apple's advertising identifier. The intended tracking answer is **No**.

## Account deletion

Telisten does not create a separate Kitta account. Removing a Telegram account or its cloud data is handled by Telegram. Signing out of Telisten removes the local authorization for that account; the Downloads screen can remove cached media.
