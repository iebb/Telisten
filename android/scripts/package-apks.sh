#!/usr/bin/env bash
# Build with Gradle first. This script only packages/signs existing build outputs.
set -euo pipefail
cd "$(dirname "$0")/.."

sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$sdk_root" && -f local.properties ]]; then
  sdk_root="$(sed -n 's/^sdk.dir=//p' local.properties)"
fi
: "${sdk_root:?Set ANDROID_HOME to the Android SDK directory}"
build_tools="$sdk_root/build-tools/36.0.0"
: "${JAVA_HOME:?Set JAVA_HOME to JDK 17}"
for artifact in app/build/outputs/apk/debug/app-debug.apk app/build/outputs/apk/release/app-release-unsigned.apk; do
  [[ -f "$artifact" ]] || { echo "Missing $artifact. Build assembleDebug and assembleRelease first." >&2; exit 1; }
done

# Always start with a fresh bundle so artifacts from older runs are not uploaded.
staging="$(mktemp -d "${TMPDIR:-/tmp}/telisten-apks.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/output"
cp app/build/outputs/apk/debug/app-debug.apk "$staging/output/telisten-debug.apk"

if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  : "${ANDROID_KEYSTORE_PASSWORD:?Missing ANDROID_KEYSTORE_PASSWORD}"
  : "${ANDROID_KEY_ALIAS:?Missing ANDROID_KEY_ALIAS}"
  : "${ANDROID_KEY_PASSWORD:?Missing ANDROID_KEY_PASSWORD}"
  export TELISTEN_SIGNING_STORE="$staging/release.keystore"
  python3 - <<'PY'
import base64, os
from pathlib import Path
p = Path(os.environ['TELISTEN_SIGNING_STORE'])
p.write_bytes(base64.b64decode(''.join(os.environ['ANDROID_KEYSTORE_BASE64'].split()), validate=True))
p.chmod(0o600)
PY
  signing_mode='Configured release key'
  release_name='telisten-release.apk'
else
  for name in ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
    [[ -z "${!name:-}" ]] || { echo "Partial signing configuration: ANDROID_KEYSTORE_BASE64 is required." >&2; exit 1; }
  done
  export TELISTEN_SIGNING_STORE="${ANDROID_USER_HOME:-$HOME/.android}/debug.keystore"
  [[ -f "$TELISTEN_SIGNING_STORE" ]] || { echo 'Build the debug APK first to generate its test signing key.' >&2; exit 1; }
  export ANDROID_KEYSTORE_PASSWORD=android ANDROID_KEY_ALIAS=androiddebugkey ANDROID_KEY_PASSWORD=android
  signing_mode='Test key (not a distribution signing identity)'
  release_name='telisten-release-test-signed.apk'
fi

"$build_tools/zipalign" -f -P 16 4 app/build/outputs/apk/release/app-release-unsigned.apk "$staging/output/$release_name"
"$build_tools/apksigner" sign --ks "$TELISTEN_SIGNING_STORE" --ks-key-alias "$ANDROID_KEY_ALIAS" \
  --ks-pass env:ANDROID_KEYSTORE_PASSWORD --key-pass env:ANDROID_KEY_PASSWORD \
  --v4-signing-enabled false "$staging/output/$release_name"
for apk in "$staging/output/"*.apk; do
  "$build_tools/apksigner" verify "$apk"
  "$build_tools/zipalign" -c -P 16 4 "$apk"
done
export TELISTEN_APK_OUTPUT="$staging/output"
python3 - <<'PY'
import hashlib, os
from pathlib import Path
folder = Path(os.environ['TELISTEN_APK_OUTPUT'])
(folder / 'SHA256SUMS').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in sorted(folder.glob('*.apk'))
))
PY
cat > "$staging/output/BUILD.txt" <<EOF2
Telisten Android APKs

Commit: ${GITHUB_SHA:-local working tree}
Release signature: $signing_mode

Both APKs are installable. APKs are universal (all supported Android ABIs).
If Telegram API credentials were absent during compilation, sign-in requires a rebuild with credentials.
CI test keys are ephemeral: use a consistent release key for updates across workflow runs.
Debug and release builds share the application ID; APKs with different signing keys cannot update each other.
EOF2
# dist contains generated artifacts only and is gitignored.
mkdir -p dist
find dist -maxdepth 1 -type f \( -name '*.apk' -o -name '*.idsig' -o -name 'SHA256SUMS' -o -name 'BUILD.txt' \) -delete
cp "$staging/output/"* dist/
printf 'Packaged %s and telisten-debug.apk in android/dist/\n' "$release_name"
