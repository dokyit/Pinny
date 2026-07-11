#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="$ROOT/.build/axraise-persistence-probe"
OUTPUT="$OUTPUT_DIRECTORY/AXRaisePersistenceProbe"

mkdir -p "$OUTPUT_DIRECTORY"

xcrun --sdk macosx swiftc \
  -target arm64-apple-macos13.0 \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT/Tools/AXRaisePersistenceProbe.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -o "$OUTPUT"

if (( $# == 0 )); then
  "$OUTPUT" --check
else
  "$OUTPUT" "$@"
fi
