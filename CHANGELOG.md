# Changelog

## 1.1.1 — 2026-07-15

- Fixed Control-. reporting failure even though macOS minimized the window.
- Fixed the resulting Control-, “no hidden window” error by recording the
  window as soon as the Accessibility minimize request succeeds.
- Deferred restore focus by one main-loop turn so macOS can apply the
  unminimize request before Pinny raises the window.

## 1.1.0 — 2026-07-15

- Added global Control-. to hide the exact focused window without hiding other
  windows from the same application.
- Added global Control-, to restore and raise the most recently hidden window.
- Added a last-hidden-first-restored stack with terminated/stale-window cleanup
  and retry-safe behavior after transient Accessibility failures.
- Added popover buttons and status/HUD feedback for hide and restore actions.
- Refactored global Carbon shortcut handling to register and dispatch three
  independent shortcuts while preserving Control-Z pin/unpin behavior.
- Expanded the executable core suite from 43 to 50 passing tests.

## 1.0.0 — 2026-07-10

- Native Apple Silicon macOS menu-bar application with no Dock icon.
- Global Control-Z shortcut for pinning one focused window at a time.
- Exact focused-window targeting through macOS Accessibility.
- Verified optional yabai/Dock backend with owner checks and compositor
  sub-layer read-back before reporting success.
- Exact original sub-layer restoration on toggle, target replacement, and
  normal application quit.
- Accessibility onboarding, Launch at Login, compact HUD feedback, template
  menu icons, and complete application icon artwork.
- 43 executable core tests covering state, identity, restoration, helper
  failures, stale/recycled IDs, drift maintenance, and command verification.

### Important

Stock macOS does not grant ordinary applications presenter rights over windows
owned by other processes. Persistent generic pinning therefore requires the
optional advanced yabai setup documented in the README, including deliberately
reduced System Integrity Protection settings. Pinny never performs those
security changes automatically.
