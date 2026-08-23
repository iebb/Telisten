#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/telisten-schema.XXXXXX")
schema_file="$temporary_dir/schema.json"
schema_index="$temporary_dir/schema.html"
generator_dir="$temporary_dir/swift-mtproto"

cleanup() {
  rm -rf -- "$temporary_dir"
}
trap cleanup EXIT HUP INT TERM

curl --fail --location --silent --show-error \
  https://core.telegram.org/schema/json \
  --output "$schema_file"

curl --fail --location --silent --show-error \
  https://core.telegram.org/schema \
  --output "$schema_index"

schema_layer=$(sed -n 's/.*Layer \([0-9][0-9]*\).*/\1/p' "$schema_index" | head -n 1)
source_layer=$(sed -n 's/.*static let layer: Int32 = \([0-9][0-9]*\).*/\1/p' "$project_dir/Telisten/Telegram/TelegramService.swift" | head -n 1)

if [ -z "$schema_layer" ] || [ "$schema_layer" != "$source_layer" ]; then
  echo "Schema layer is ${schema_layer:-unknown}; TelegramService expects ${source_layer:-unknown}." >&2
  echo "Review Telegram's layer changes and update TelegramService before regenerating." >&2
  exit 1
fi

git clone --quiet --depth 1 --branch 1.0.0 \
  https://github.com/UInt8Co/swift-mtproto.git \
  "$generator_dir"

swift run --package-path "$generator_dir" mtproto-gen-swift \
  --schema-url "$schema_file" \
  --output "$project_dir/Generated/TelegramAPI" \
  --mode client \
  --visibility public \
  --methods-file "$project_dir/telegram-methods.txt"
