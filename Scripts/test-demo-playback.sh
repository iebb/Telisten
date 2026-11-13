#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/telisten-demo-build.XXXXXX")
trap 'rm -f "$test_directory/demo-playback-tests"; rmdir "$test_directory" 2>/dev/null || true' EXIT
# Demo mode only exists in Debug builds, so compile the sources with DEBUG set.
xcrun swiftc -swift-version 6 -parse-as-library -D DEBUG \
  Telisten/Core/Models.swift Telisten/Core/Formatting.swift Telisten/Core/AppConfiguration.swift \
  Telisten/Player/StreamingAudioResource.swift Telisten/Player/AudioPlayer.swift \
  Telisten/Player/DemoAudioSample.swift \
  Tests/DemoPlaybackTests.swift -o "$test_directory/demo-playback-tests"
python3 - "$test_directory/demo-playback-tests" <<'PYTEST'
import subprocess
import sys
subprocess.run(sys.argv[1:], check=True, timeout=60)
PYTEST
