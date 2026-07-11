#!/bin/zsh
set -u

YABAI="${PINNY_YABAI_PATH:-}"
if [[ -z "$YABAI" ]]; then
  if [[ -x /opt/homebrew/bin/yabai ]]; then
    YABAI=/opt/homebrew/bin/yabai
  elif [[ -x /usr/local/bin/yabai ]]; then
    YABAI=/usr/local/bin/yabai
  fi
fi

failures=0

if [[ -n "$YABAI" && -x "$YABAI" ]]; then
  echo "PASS  yabai executable: $YABAI ($($YABAI --version))"
else
  echo "FAIL  yabai executable not found"
  failures=$((failures + 1))
fi

sip_status="$(csrutil status 2>&1)"
if [[ "$sip_status" == *"Filesystem Protections: disabled"* &&
      "$sip_status" == *"Debugging Restrictions: disabled"* &&
      "$sip_status" == *"NVRAM Protections: disabled"* ]]; then
  echo "PASS  required partial SIP components are disabled"
else
  echo "FAIL  partial SIP state is not ready (fs, debug, and nvram must be disabled)"
  failures=$((failures + 1))
fi

boot_arguments="$(nvram boot-args 2>/dev/null || true)"
if [[ "$boot_arguments" == *"-arm64e_preview_abi"* ]]; then
  echo "PASS  arm64e preview boot argument is present"
else
  echo "FAIL  -arm64e_preview_abi boot argument is absent"
  failures=$((failures + 1))
fi

if [[ -d /Library/ScriptingAdditions/yabai.osax ]]; then
  echo "PASS  yabai scripting addition is installed"
else
  echo "FAIL  yabai scripting addition is not installed"
  failures=$((failures + 1))
fi

if [[ -n "$YABAI" && -x "$YABAI" ]] && "$YABAI" -m query --windows >/dev/null 2>&1; then
  echo "PASS  yabai service accepts messages"
else
  echo "FAIL  yabai service is not running or not accepting messages"
  failures=$((failures + 1))
fi

# A scripting addition can exist on disk while its live Dock payload is not
# connected. Re-applying a window's current sub-layer is an observable no-op
# that verifies the privileged command path without changing window state.
if [[ -n "$YABAI" && -x "$YABAI" ]]; then
  target="$($YABAI -m query --windows 2>/dev/null | /usr/bin/python3 -c '
import json, sys
blocked = {"Dock", "Pinny", "System Settings", "WindowManager"}
try:
    windows = json.load(sys.stdin)
except Exception:
    windows = []
candidates = [w for w in windows if w.get("app") not in blocked and w.get("role") == "AXWindow" and w.get("sub-layer") in {"below", "normal", "above"}]
candidates.sort(key=lambda w: (not w.get("has-focus", False), not w.get("is-visible", False)))
if candidates:
    print(candidates[0]["id"], candidates[0]["sub-layer"])
' 2>/dev/null || true)"
  if [[ -n "$target" ]]; then
    window_id="${target%% *}"
    current_sub_layer="${target#* }"
    if "$YABAI" -m window "$window_id" --sub-layer "$current_sub_layer" >/dev/null 2>&1; then
      echo "PASS  live Dock scripting addition accepts sub-layer commands"
    else
      echo "FAIL  scripting addition is installed but not active in Dock"
      failures=$((failures + 1))
    fi
  else
    echo "FAIL  no safe application window was available to verify the Dock payload"
    failures=$((failures + 1))
  fi
fi

if (( failures == 0 )); then
  echo "READY Pinny can attempt a verified window sub-layer change."
  exit 0
fi

echo "NOT READY ($failures prerequisite checks failed)."
echo "Pinny will not alter SIP, NVRAM, launchd, sudoers, or Dock injection automatically."
exit 1
