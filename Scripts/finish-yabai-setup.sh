#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
YABAI="${PINNY_YABAI_PATH:-/opt/homebrew/bin/yabai}"
SUDOERS_FILE="/private/etc/sudoers.d/yabai"

if [[ ! -x "$YABAI" ]]; then
  echo "yabai is not installed at $YABAI" >&2
  exit 1
fi

sip_status="$(csrutil status 2>&1)"
if [[ "$sip_status" != *"Filesystem Protections: disabled"* ||
      "$sip_status" != *"Debugging Restrictions: disabled"* ||
      "$sip_status" != *"NVRAM Protections: disabled"* ]]; then
  echo "Required partial SIP state is missing." >&2
  echo "Run this in RecoveryOS Terminal, then reboot:" >&2
  echo "  csrutil enable --without fs --without debug --without nvram" >&2
  exit 1
fi

boot_arguments="$(nvram boot-args 2>/dev/null || true)"
if [[ "$boot_arguments" != *"-arm64e_preview_abi"* ]]; then
  echo "The -arm64e_preview_abi boot argument is missing." >&2
  echo "Run: sudo nvram boot-args=-arm64e_preview_abi" >&2
  echo "Then reboot and run this script again." >&2
  exit 1
fi

hash="$(shasum -a 256 "$YABAI" | awk '{print $1}')"
rule="$(whoami) ALL=(root) NOPASSWD: sha256:$hash $YABAI --load-sa"
temporary_rule="$(mktemp -t pinny-yabai-sudoers)"
trap 'rm -f "$temporary_rule"' EXIT
print -r -- "$rule" > "$temporary_rule"
/usr/sbin/visudo -cf "$temporary_rule"

echo "Installing a checksum-pinned sudoers rule for only: yabai --load-sa"
sudo /usr/bin/install -o root -g wheel -m 0440 "$temporary_rule" "$SUDOERS_FILE"

# The daemon must be running before Dock's payload connects to its socket.
# Restarting the daemon after injection strands the payload on a dead socket.
"$YABAI" --restart-service
for attempt in 1 2 3 4 5; do
  sleep 1
  "$YABAI" -m query --displays >/dev/null 2>&1 && break
done

sudo "$YABAI" --load-sa
sleep 1

"$ROOT/Scripts/check-yabai-backend.sh"
echo "yabai's Dock scripting addition is configured. Pinny can now verify real pin operations."
