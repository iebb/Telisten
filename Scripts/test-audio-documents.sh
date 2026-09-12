#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/telisten-audio-build.XXXXXX")
trap 'rm -f "$test_directory/audio-document-tests"; rmdir "$test_directory"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Telisten/Core/Models.swift Telisten/Player/StreamingAudioResource.swift \
  Tests/AudioDocumentTests.swift \
  -o "$test_directory/audio-document-tests"
python3 - "$test_directory/audio-document-tests" <<'PYTEST'
import subprocess
import sys
subprocess.run(sys.argv[1:], check=True, timeout=30)
PYTEST
