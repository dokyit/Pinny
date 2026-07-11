#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="$ROOT/.build/pinning-probe"
OUTPUT="$OUTPUT_DIRECTORY/PinningProbe"

mkdir -p "$OUTPUT_DIRECTORY"

xcrun --sdk macosx swiftc \
  -target arm64-apple-macos13.0 \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT/Tools/PinningProbe.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -o "$OUTPUT"

"$OUTPUT" "$@"
