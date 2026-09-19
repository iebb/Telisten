#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/telisten-cache-build.XXXXXX")
trap 'rm -f "$test_directory/cache-tests"; rmdir "$test_directory" 2>/dev/null || true' EXIT
xcrun swiftc -swift-version 6 -parse-as-library \
  Telisten/Core/Models.swift Telisten/Storage/CacheStore.swift \
  Tests/CacheStoreTests.swift -o "$test_directory/cache-tests"
"$test_directory/cache-tests"
