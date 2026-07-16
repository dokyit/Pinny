#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="$ROOT/.build/core-tests"
OUTPUT="$OUTPUT_DIRECTORY/PinnyCoreTests"

mkdir -p "$OUTPUT_DIRECTORY"

xcrun --sdk macosx swiftc \
  -target arm64-apple-macos13.0 \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT/Pinny/Models/AppStatus.swift" \
  "$ROOT/Pinny/Models/HotKeyConfiguration.swift" \
  "$ROOT/Pinny/Models/WindowModels.swift" \
  "$ROOT/Pinny/Services/PreferencesStore.swift" \
  "$ROOT/Pinny/Services/ShortcutActionRouter.swift" \
  "$ROOT/Pinny/Services/UnsupportedWindowFilter.swift" \
  "$ROOT/Pinny/Services/WindowLevelController.swift" \
  "$ROOT/Pinny/Services/YabaiWindowService.swift" \
  "$ROOT/Pinny/Services/WindowPinManager.swift" \
  "$ROOT/Pinny/Services/WindowVisibilityManager.swift" \
  "$ROOT/Tools/CoreTestRunner.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework Carbon \
  -framework CoreGraphics \
  -o "$OUTPUT"

"$OUTPUT"
