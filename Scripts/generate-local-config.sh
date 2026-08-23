#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
environment_file="$project_dir/.env"
output_directory="$project_dir/.local"
output_file="$output_directory/Telegram.xcconfig"

if [ ! -f "$environment_file" ]; then
  echo "Missing $environment_file. Copy .env.example to .env and add the Telegram app credentials." >&2
  exit 1
fi

read_value() {
  sed -n "s/^$1=//p" "$environment_file" | tail -n 1 | sed 's/^"//; s/"$//'
}

api_id=$(read_value TELEGRAM_API_ID)
api_hash=$(read_value TELEGRAM_API_HASH)

case "$api_id" in
  ''|*[!0-9]*)
    echo "TELEGRAM_API_ID must be a positive integer." >&2
    exit 1
    ;;
esac

if [ "$api_id" -le 0 ] || [ "$api_id" -gt 2147483647 ]; then
  echo "TELEGRAM_API_ID must fit in a positive 32-bit integer." >&2
  exit 1
fi

case "$api_hash" in
  *[!0-9a-fA-F]*)
    echo "TELEGRAM_API_HASH must contain exactly 32 hexadecimal characters." >&2
    exit 1
    ;;
esac

if [ "${#api_hash}" -ne 32 ]; then
  echo "TELEGRAM_API_HASH must contain exactly 32 hexadecimal characters." >&2
  exit 1
fi

mkdir -p "$output_directory"
umask 077
{
  printf 'TELEGRAM_API_ID = %s\n' "$api_id"
  printf 'TELEGRAM_API_HASH = %s\n' "$api_hash"
} > "$output_file"
