#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD_ROOT="$ROOT/build/Local"
APP="$BUILD_ROOT/Pinny.app"
CONTENTS="$APP/Contents"

COMPILER_FLAGS=(-warnings-as-errors)
if [[ "${PINNY_RELEASE:-0}" == "1" ]]; then
  COMPILER_FLAGS+=(-O -whole-module-optimization)
else
  COMPILER_FLAGS+=(-Onone)
fi

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

SOURCES=(
  "$ROOT/Pinny/App/AppCoordinator.swift"
  "$ROOT/Pinny/App/AppModel.swift"
  "$ROOT/Pinny/App/PinnyApp.swift"
  "$ROOT/Pinny/Models/AppStatus.swift"
  "$ROOT/Pinny/Models/HotKeyConfiguration.swift"
  "$ROOT/Pinny/Models/WindowModels.swift"
  "$ROOT/Pinny/Services/AccessibilityPermissionManager.swift"
  "$ROOT/Pinny/Services/FocusedWindowManager.swift"
  "$ROOT/Pinny/Services/HotKeyManager.swift"
  "$ROOT/Pinny/Services/LaunchAtLoginManager.swift"
  "$ROOT/Pinny/Services/NotificationManager.swift"
  "$ROOT/Pinny/Services/PinnyLogger.swift"
  "$ROOT/Pinny/Services/PreferencesStore.swift"
  "$ROOT/Pinny/Services/ShortcutActionRouter.swift"
  "$ROOT/Pinny/Services/UnsupportedWindowFilter.swift"
  "$ROOT/Pinny/Services/WindowLevelController.swift"
  "$ROOT/Pinny/Services/YabaiWindowService.swift"
  "$ROOT/Pinny/Services/WindowPinManager.swift"
  "$ROOT/Pinny/Services/WindowRaiseManager.swift"
  "$ROOT/Pinny/UI/MenuBarController.swift"
  "$ROOT/Pinny/UI/MenuBarView.swift"
  "$ROOT/Pinny/UI/ResourceLocator.swift"
)

xcrun --sdk macosx swiftc \
  -target arm64-apple-macos13.0 \
  -swift-version 5 \
  -parse-as-library \
  -module-name Pinny \
  "${COMPILER_FLAGS[@]}" \
  "${SOURCES[@]}" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework Carbon \
  -framework CoreGraphics \
  -framework ServiceManagement \
  -framework SwiftUI \
  -o "$CONTENTS/MacOS/Pinny"

cp "$ROOT/Pinny/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Pinny" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.pinnyutility.Pinny" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Pinny" "$CONTENTS/Info.plist"

cp "$ROOT/Pinny/Resources/RuntimeAssets/MenuBarIdle.png" "$CONTENTS/Resources/"
cp "$ROOT/Pinny/Resources/RuntimeAssets/MenuBarPinned.png" "$CONTENTS/Resources/"
cp "$ROOT/Pinny/Resources/RuntimeAssets/Pinny.icns" "$CONTENTS/Resources/"

codesign \
  --force \
  --sign - \
  --options runtime \
  --entitlements "$ROOT/Pinny/Pinny.entitlements" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
plutil -lint "$CONTENTS/Info.plist"
file "$CONTENTS/MacOS/Pinny"

echo "Built $APP"
