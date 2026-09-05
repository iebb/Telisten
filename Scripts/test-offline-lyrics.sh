#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/telisten-lyrics-build.XXXXXX")
trap 'rmdir "$test_directory" 2>/dev/null || true' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Telisten/Core/Models.swift Telisten/Lyrics/LyricsService.swift \
  Tests/OfflineLyricsTests.swift -o "$test_directory/offline-lyrics-tests"
"$test_directory/offline-lyrics-tests"
rm "$test_directory/offline-lyrics-tests"
