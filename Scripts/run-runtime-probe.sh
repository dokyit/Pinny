#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="$ROOT/.build/runtime-probe"
OUTPUT="$OUTPUT_DIRECTORY/RuntimeProbe"

mkdir -p "$OUTPUT_DIRECTORY"

xcrun --sdk macosx swiftc \
  -target arm64-apple-macos13.0 \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT/Tools/RuntimeProbe.swift" \
  -framework AppKit \
  -framework CoreGraphics \
  -o "$OUTPUT"

"$OUTPUT" "${1:-com.pinnyutility.Pinny}"
