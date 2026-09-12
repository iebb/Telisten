#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/telisten-playback-build.XXXXXX")
trap 'rm -f "$test_directory/playback-tests"; rmdir "$test_directory"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Telisten/Core/Models.swift Telisten/Core/Formatting.swift \
  Telisten/Player/StreamingAudioResource.swift Telisten/Player/AudioPlayer.swift \
  Tests/PlaybackRegressionTests.swift -o "$test_directory/playback-tests"
"$test_directory/playback-tests"
