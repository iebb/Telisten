#!/bin/sh
set -eu

repository_path=${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
cd "$repository_path"

: "${TELEGRAM_API_ID:?Set TELEGRAM_API_ID in the Xcode Cloud workflow environment}"
: "${TELEGRAM_API_HASH:?Set TELEGRAM_API_HASH in the Xcode Cloud workflow environment}"

./Scripts/generate-local-config.sh
