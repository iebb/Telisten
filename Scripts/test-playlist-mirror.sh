#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/telisten-playlist-build.XXXXXX")
trap 'rmdir "$test_directory" 2>/dev/null || true' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Telisten/Core/Models.swift Telisten/Storage/LocalLibraryStore.swift \
  Tests/PlaylistMirrorTests.swift -o "$test_directory/playlist-mirror-tests"
"$test_directory/playlist-mirror-tests"
rm "$test_directory/playlist-mirror-tests"
