#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIRECTORY="$ROOT/.build/menu-preview"
OUTPUT="$OUTPUT_DIRECTORY/MenuPreviewRenderer"
PREVIEW_DIRECTORY="$ROOT/build/MenuPreviews"

mkdir -p "$OUTPUT_DIRECTORY" "$PREVIEW_DIRECTORY"

xcrun --sdk macosx swiftc \
  -target arm64-apple-macos13.0 \
  -swift-version 5 \
  -parse-as-library \
  "$ROOT/Pinny/App/AppModel.swift" \
  "$ROOT/Pinny/Models/AppStatus.swift" \
  "$ROOT/Pinny/Models/HotKeyConfiguration.swift" \
  "$ROOT/Pinny/Models/WindowModels.swift" \
  "$ROOT/Pinny/UI/MenuBarController.swift" \
  "$ROOT/Pinny/UI/MenuBarView.swift" \
  "$ROOT/Pinny/UI/ResourceLocator.swift" \
  "$ROOT/Tools/MenuPreviewRenderer.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework Carbon \
  -framework SwiftUI \
  -o "$OUTPUT"

"$OUTPUT" "$PREVIEW_DIRECTORY"
