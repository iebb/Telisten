#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p app/libs
artifact=app/libs/tdlib-0.1.0.aar
curl --fail --location --retry 3 'https://github.com/AkashPriyadarshii/tdlib-android/releases/download/v0.1.0/core-release.aar' -o "$artifact.tmp"
printf '%s  %s\n' '5a5ad7fa346a29f3f09a31eaf4a742dbab864f25dc74f5373f7d2708e2a27638' "$artifact.tmp" | shasum -a 256 -c -
mv "$artifact.tmp" "$artifact"
