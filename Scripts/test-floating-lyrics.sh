#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/telisten-floating-lyrics.XXXXXX")
trap 'rm -f "$test_directory/lyrics-tests"; rmdir "$test_directory"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Telisten/Core/Models.swift Telisten/Lyrics/FloatingLyricExcerpt.swift \
  Tests/FloatingLyricsTests.swift -o "$test_directory/lyrics-tests"
"$test_directory/lyrics-tests"
