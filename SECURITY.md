# Credentials and public-source checklist

## Source and local development

Apple and Android share this repository and the ignored root `.env`. Only the non-functional `.env.example` belongs in Git. Generated `.local/Telegram.xcconfig`, Android `local.properties`, signing keys, service-account JSON, provisioning profiles, downloaded dependencies, build outputs, and session data must stay out of Git.

Telegram application IDs/hashes are embedded in native app binaries and can be extracted. GitHub secrets keep these values out of source, not out of distributed apps. User Telegram authorization keys, login codes, 2FA passwords, signing private keys, and publishing credentials must never appear in source, screenshots, logs, or artifacts.

## GitHub CI

Repository Actions secrets used by both platforms:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`

Android APK signing additionally uses:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

The Play publishing service account is not needed by build CI and must not be uploaded as a build artifact. Existing APK workflows do not publish to Play. Apple verification builds are unsigned and need no signing or App Store Connect key. Xcode Cloud distribution uses its own secret environment variables; GitHub Actions secrets are not automatically shared with it.

Pull requests receive none of these secrets, including same-repository PRs. Do not change builds to `pull_request_target` or run unreviewed code with signing credentials. Restrict who can push `master` and `android-v*` tags. Review workflow, build-script, and dependency changes before merging. Build actions use read-only permissions and do not persist checkout credentials; Android dependencies and the Gradle wrapper are checksum-pinned. Do not cache generated credential configuration or upload complete build directories.

## Before making the repository public

1. Run `gitleaks git --redact=100 --log-opts='--all' .` with Gitleaks 8.30.1 or newer. The only configured exception is the exact dummy hash in `.env.example`.
2. Scan a clean checkout with `gitleaks dir --redact=100 .`; do not scan ignored private local configuration into a public report. The `Secret scan` workflow performs both checks on each push/PR.
3. Inspect tracked files, historical files, screenshots, releases, issues, and existing Actions logs/artifacts for private information. Secret scanning is not a guarantee and does not read screenshot text.
4. If any real credential was committed, revoke/rotate it first and coordinate history cleanup before publication. Removing it from the latest version does not remove it from history.
5. Enable GitHub secret scanning/push protection where available; require the CI checks and review on `master`. Review outside-collaborator and Actions permissions.
6. Choose a source license before describing the repository as open source. Public visibility alone does not grant reuse rights; no project-wide source license is selected yet. Review bundled media and dependency redistribution notices separately.

Publication is a separate owner action; CI never changes repository visibility. Report security issues privately to the maintainer, not in a public issue containing credentials or session data.
