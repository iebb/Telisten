#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
environment_file="$project_dir/.env"
output_directory="$project_dir/.local"
output_file="$output_directory/Telegram.xcconfig"

read_value() {
  sed -n "s/^$1=//p" "$environment_file" | tail -n 1 | sed 's/^"//; s/"$//'
}

if [ -n "${TELEGRAM_API_ID:-}" ] && [ -n "${TELEGRAM_API_HASH:-}" ]; then
  api_id=$TELEGRAM_API_ID
  api_hash=$TELEGRAM_API_HASH
elif [ -f "$environment_file" ]; then
  api_id=$(read_value TELEGRAM_API_ID)
  api_hash=$(read_value TELEGRAM_API_HASH)
else
  echo "Missing Telegram credentials. Set TELEGRAM_API_ID and TELEGRAM_API_HASH, or copy .env.example to .env." >&2
  exit 1
fi

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
