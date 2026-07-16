<p align="center">
  <img src="Pinny/Resources/IconSource/AppIcon.svg" width="180" alt="Pinny application icon">
</p>

<h1 align="center">Pinny</h1>

<p align="center">
  Pin, hide, and restore focused macOS windows with global Control shortcuts.
</p>

<p align="center">
  <a href="https://github.com/dokyit/Pinny/releases/latest">Download the latest release</a>
  ·
  <a href="#advanced-yabai-setup">Advanced setup</a>
  ·
  <a href="LICENSE">MIT License</a>
</p>

Pinny is a native Swift menu-bar utility for Apple Silicon Macs. It runs as an
`LSUIElement` accessory app. It registers **Control-Z** (`⌃Z`) to toggle a
pin, **Control-.** (`⌃.`) to hide the focused window, and **Control-,** (`⌃,`)
to restore the most recently hidden window. Pinny uses the macOS Accessibility
API to identify exact windows and can ask an optional, separately configured
[yabai](https://github.com/asmvik/yabai) service to keep a pinned window in
yabai's `above` compositor sub-layer.

> [!IMPORTANT]
> Arbitrary third-party always-on-top is not available to an ordinary macOS
> app. Public Accessibility and Core Graphics APIs cannot set another app's
> persistent window level. Direct private CGS/SLS calls were also tested on this
> Mac: they returned apparent success but did not change WindowServer's
> presentation state because Pinny's connection lacked presenter rights.
>
> Pinny's generic backend therefore depends on a user-installed yabai scripting
> addition running inside Dock. On Apple Silicon macOS 26 Tahoe, yabai's current
> instructions require deliberately weakening parts of System Integrity
> Protection, changing NVRAM/boot-argument policy, and authorizing privileged
> Dock injection. **Pinny never performs any of those changes for you.** Read
> [Advanced yabai setup](#advanced-yabai-setup) before deciding whether that
> trade-off is acceptable.

## Status

| Capability | Status |
| --- | --- |
| Native arm64 app, macOS 13+ | Implemented |
| Menu-bar-only process; no Dock icon | Implemented and process-classification tested |
| Focused application and individual AX window lookup | Implemented and live-probed |
| Global `⌃Z`, `⌃.`, and `⌃,` registration | Implemented with Carbon, independent duplicate detection, routing, and clean unregister |
| Hide/restore exact windows | Implemented with the AX minimize setter and a last-hidden-first-restored stack; does not hide unrelated windows from the same app |
| Generic third-party always-on-top | Implemented and live-validated through the optional yabai backend (`normal 0 → above 3 → normal 0`) |
| Public-only fallback | **Raise Current Window Once (Fallback)** uses `AXRaise`; controlled testing proved that it does not stay above an active window from another app |
| Accessibility onboarding | Implemented |
| Launch at Login | Implemented with `SMAppService.mainApp` |
| Restore on unpin/quit | Implemented for yabai state, with owner validation, read-back verification, and retry; destructive helper setup remains entirely manual |

Pinny controls one window at a time. Pinning a different window first restores
the previous window. It does not persist AX references or try to restore a pin
after Pinny or macOS restarts.

## Install the DMG

Download `Pinny-1.1.1-arm64.dmg` from the
[latest GitHub Release](https://github.com/dokyit/Pinny/releases/latest).

1. Open the DMG.
2. Drag **Pinny.app** onto the **Applications** shortcut.
3. Launch `/Applications/Pinny.app` and grant Accessibility permission.

This build is ad-hoc signed rather than Developer ID-notarized. If Gatekeeper
blocks the first launch, use **System Settings > Privacy & Security > Open
Anyway**. The matching SHA-256 checksum is attached to the release.

## Requirements

### Base app

- Apple Silicon (`arm64`)
- macOS 13 Ventura or later
- Accessibility permission for Pinny
- A normal logged-in Aqua session

Pinny rejects its own UI and known protected surfaces such as Dock, menu bar,
Control Center, Notification Center, login/security UI, and desktop processes.
Full-screen Spaces and system-protected windows remain subject to macOS and
yabai restrictions.

### Generic pinning

In addition to the base requirements, persistent third-party pinning needs:

- yabai in `/opt/homebrew/bin/yabai`, `/usr/local/bin/yabai`, or the path named
  by `PINNY_YABAI_PATH`;
- the yabai user service running and Accessibility-approved;
- yabai's scripting addition loaded into Dock; and
- the Apple Silicon security configuration required by yabai for window-layer
  control.

Installing the executable alone is insufficient. If the service, socket, or
scripting addition is absent, Pinny reports an actionable failure and does not
claim the window is pinned.

## Build

The repository has no Swift package dependencies. Full Xcode is recommended,
but an Apple Command Line Tools-only local bundle script is included.

### Full Xcode

Open `Pinny.xcodeproj`, select the shared **Pinny** scheme and **My Mac**, then
choose Product > Build or Product > Run. The equivalent command is:

```sh
cd /path/to/Pinny
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

xcodebuild \
  -project Pinny.xcodeproj \
  -scheme Pinny \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$PWD/build/XcodeDerivedData" \
  build
```

Run the Xcode tests with the same arguments followed by `test`. Full Xcode was
not installed on the validation Mac, so these exact commands remain pending
there.

### Command Line Tools

```sh
cd /path/to/Pinny

swift build
./Scripts/run-core-tests.sh
./Scripts/build-local.sh
./Scripts/create-dmg.sh
open "$PWD/build/Local/Pinny.app"
```

`Scripts/build-local.sh` creates an arm64 macOS 13+ app, copies the runtime
assets, applies an ad-hoc hardened-runtime signature, and validates its plist,
signature, and architecture. Ad-hoc signing is only for local development.

Useful diagnostics:

```sh
# Safe symbol/load checks; neither command changes a foreign window.
./Scripts/run-private-window-level-probe.sh --symbol-check
./Scripts/run-axraise-persistence-probe.sh --check

# Runtime classification, with Pinny already running.
./Scripts/run-runtime-probe.sh

# Public AX inventory; --perform-raise is explicitly one-shot.
./Scripts/run-pinning-probe.sh
./Scripts/run-pinning-probe.sh --perform-raise

# Native SwiftUI menu-state renders.
./Scripts/render-menu-previews.sh
```

The `--live` probe modes alter foreground windows temporarily. Read their source
and close sensitive work before using them.

## Install and grant Accessibility

1. Build Pinny and put one stable copy at `/Applications/Pinny.app`.
2. Launch it. A pushpin appears in the menu bar; no Dock icon or normal app
   window is expected.
3. Open the popover and choose **Request Permission** or **Open Settings**.
4. In **System Settings > Privacy & Security > Accessibility**, add and enable
   the exact `/Applications/Pinny.app` copy.
5. Quit and relaunch Pinny if macOS does not apply trust to the running process.

Development rebuilds can invalidate a TCC grant when the path or signature
changes. For development only, this removes the existing Accessibility grant so
it can be granted again:

```sh
tccutil reset Accessibility com.pinnyutility.Pinny
```

## Use

1. Focus a normal window in another application.
2. Press the physical **Control** key and **Z**.
3. With a working yabai scripting addition, Pinny maps that exact AX window to a
   `CGWindowID`, changes only that window to `--sub-layer above`, reads it back,
   and then displays `Pinned`.
4. Focus the same window and press `⌃Z` again to restore its recorded original
   sub-layer.

Window visibility shortcuts do not require yabai:

- Press **Control-.** (`⌃.`) to hide (minimize) the focused individual window.
- Press **Control-,** (`⌃,`) to restore and raise the most recently hidden
  surviving window.
- Repeated hides form a stack, so repeated restores bring them back in reverse
  order. Closing an application safely removes its remembered windows. The
  stack is process-local and resets when Pinny quits or restarts; already
  minimized windows remain minimized.

Opening Pinny's popover does not intentionally select Pinny as the target; it
remembers the last external application. If another process already owns the
same global shortcut, the popover reports shortcut registration failure.

The separate **Raise Current Window Once (Fallback)** action is never treated as
a pin. A successful AX result does not mean the window moved above a foreground
window from another application.

## Advanced yabai setup

This section documents upstream requirements so the backend is reproducible. It
is not an instruction that Pinny runs automatically, and it is not a security
recommendation. Check your organization's policy and make a backup first.

The authoritative sources are:

- [yabai repository and current supported systems](https://github.com/asmvik/yabai)
- [Installing the latest release and configuring the scripting addition](https://github.com/asmvik/yabai/wiki/Installing-yabai-%28latest-release%29)
- [Disabling System Integrity Protection for privileged features](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection)
- [Current command reference](https://github.com/asmvik/yabai/blob/master/doc/yabai.asciidoc)
- [Upstream uninstall procedure](https://github.com/asmvik/yabai/wiki/Uninstalling-yabai)

As of the upstream pages reviewed on July 10, 2026, controlling window layers is
one of the features that requires partial SIP disablement and the Dock scripting
addition. On Apple Silicon macOS 13 or newer, the documented Recovery command
is:

```sh
# RecoveryOS Terminal — NOT run by Pinny
csrutil enable --without fs --without debug --without nvram
```

After rebooting normally, upstream also requires the arm64e preview ABI boot
argument and another reboot:

```sh
# Normal macOS Terminal — NOT run by Pinny
sudo nvram boot-args=-arm64e_preview_abi
```

That command can overwrite an existing `boot-args` value. Record the old value
first and do not proceed if you do not understand how to restore it.

Install the current release and start its user service:

```sh
brew install asmvik/formulae/yabai
yabai --start-service
```

Approve yabai itself in Accessibility, then follow the upstream installation
page to authorize only `yabai --load-sa` through a checksum-pinned sudoers rule:

```sh
sudo visudo -f /private/etc/sudoers.d/yabai
```

The rule format documented upstream is:

```text
<user> ALL=(root) NOPASSWD: sha256:<hash> <absolute-yabai-path> --load-sa
```

The hash must be updated when yabai changes. The included setup script validates
the required state, installs that narrow rule, starts the daemon before loading
Dock's payload, and verifies the live command path:

```sh
./Scripts/finish-yabai-setup.sh
```

The ordering matters: restarting yabai after loading the Dock payload severs
its socket. The daemon must start first, followed by `sudo yabai --load-sa`.
`~/.yabairc` should load the payload on daemon start and register a
`dock_did_restart` reload signal.

The current yabai syntax used by Pinny is:

```sh
yabai -m window <window-id> --sub-layer above
yabai -m window <window-id> --sub-layer normal  # example exact restore
yabai -m window <window-id> --sub-layer auto    # relinquish manual control
```

`--sub-layer`, not the older `--layer`, is the current command. Valid values are
`below`, `normal`, `above`, and `auto`; upstream explicitly marks this command as
requiring partial SIP disablement.

### State of the validation Mac

The complete advanced path was live-validated on this configuration:

| Item | Observed July 10, 2026 |
| --- | --- |
| Machine | arm64, macOS 26.5.2 build 25F84 |
| yabai executable | `/opt/homebrew/bin/yabai`, `yabai-v7.1.25` |
| yabai service/socket | Running and accepting messages |
| SIP | `unknown (Custom Configuration)` with filesystem, debugging, NVRAM, and boot-argument restrictions disabled as required upstream |
| `boot-args` | `-arm64e_preview_abi` |
| Dock scripting addition | Installed, loaded, and accepting live sub-layer commands |
| Reversible window test | ChatGPT `normal (0) → above (3) → normal (0)` |

Pinny itself still never changes SIP, NVRAM, sudoers, or Dock injection. Those
advanced prerequisites remain an explicit user-administered choice.

## Pin and restore safety

The optional backend is deliberately narrow:

- It maps the focused AX element to one numeric WindowServer ID.
- It queries yabai and requires the returned PID to match the AX owner before
  mutation.
- It accepts only known original sub-layers (`below`, `normal`, or `above`).
- It records the target PID, window ID, and exact original sub-layer.
- It requests `above`, then queries yabai again before reporting success.
- It restores the exact recorded sub-layer on toggle, replacement, or quit and
  verifies the result, retrying restoration once.
- A one-second maintenance check re-applies `above` if another actor changes it.
- If a numeric window ID is recycled to another PID, Pinny refuses to touch the
  new owner's window.
- If the target disappears, state is cleared. Transient helper failures retain
  state so a later restore can still be attempted.

If verification after a pin request fails, Pinny attempts immediate rollback and
reports failure. A helper/Dock/macOS crash can still prevent restoration; no
private or injected mechanism can promise cleanup after every crash. For manual
recovery, use yabai's current `--sub-layer auto` command on the affected window
or restart the owning application.

## Verified platform findings

Tests on the validation Mac established the following:

- Public AX exposes no writable `AXWindowLevel`; the raw query returned
  `kAXErrorAttributeUnsupported` (`-25205`).
- A controlled Codex test performed `AXRaise` successfully 10/10 times while a
  normal window from the probe app covered it. Codex remained rank 23, the cover
  remained rank 20, Codex was above the cover 0/10 times, and focus never
  changed.
- For ChatGPT/Codex windows 1202 and 3077, direct private
  `CGSSetWindowLevel(..., 3)` returned `0` and `CGSGetWindowLevel` echoed `3`.
  Nevertheless, independent SLS iteration, `kCGWindowLayer`, and cross-app
  z-order all remained at normal layer `0`; unified logging recorded a missing
  presenter-right denial. Getter echo alone was a false-success signal.
- Attempts with owner/Dock connection IDs, window groups, sub-levels,
  transactions, and ordering variants also no-op'd or failed. Direct CGS/SLS is
  not a production backend.

See [Documentation/PINNING_FEASIBILITY.md](Documentation/PINNING_FEASIBILITY.md)
for the full analysis and
[Documentation/VALIDATION_REPORT.md](Documentation/VALIDATION_REPORT.md) for the
evidence ledger. The hands-on release checklist is in
[Documentation/MANUAL_TESTS.md](Documentation/MANUAL_TESTS.md).

## Spaces and full screen

`above` means above ordinary windows in the same WindowServer presentation
context. It does not grant ownership of another Space, bypass secure/system UI,
or guarantee visibility above a native full-screen application. Pinny does not
automatically make a target sticky across Spaces. Test Mission Control, multiple
displays, Stage Manager, minimize/restore, and full screen for every macOS/yabai
combination you intend to support.

## Launch at Login

Install Pinny at `/Applications/Pinny.app` before enabling this option. The
toggle reads `SMAppService.mainApp` status. If macOS reports `requiresApproval`,
approve Pinny in **System Settings > General > Login Items**. Launch at Login
starts Pinny only; it does not install, start, elevate, or inject yabai.

## Signing and distribution

The local script's ad-hoc signature is not for distribution. Shipping to other
Macs requires a stable bundle, Developer ID Application signing, hardened
runtime, notarization, and stapling. The optional helper also makes this a poor
fit for App Store distribution: Pinny does not bundle yabai, and users must make
their own explicit security decision and configure it independently.

## Architecture

| Component | Responsibility |
| --- | --- |
| `AppCoordinator` / `AppModel` | Lifecycle, UI state, action routing, maintenance |
| `MenuBarController` / `MenuBarView` | Status item and compact popover |
| `HotKeyManager` | Global Carbon registration, independent action dispatch, and cleanup for all three shortcuts |
| `AccessibilityPermissionManager` | Trust checks, prompt, Settings deep link |
| `FocusedWindowManager` | External focused AX window lookup and protected-target filtering |
| `WindowPinManager` | One-window toggle state, replacement, cleanup |
| `YabaiWindowLevelController` | Owner-safe pin, verification, maintenance, exact restore |
| `YabaiWindowService` | Narrow `yabai -m` process client and AX-to-window-ID mapping |
| `WindowRaiseManager` | Explicit one-shot public `AXRaise` fallback |
| `WindowVisibilityManager` | Verified individual-window minimize/restore stack and stale-target cleanup |
| `LaunchAtLoginManager` | `SMAppService.mainApp` status and mutation |
| `NotificationManager` | Small nonactivating HUD |

## Troubleshooting

### `Unable to pin this window`

Read the detail in the popover. Common causes are a missing Accessibility grant,
protected/no focused window, absent yabai binary, stopped yabai socket, unloaded
scripting addition, stale/recycled window ID, or a failed read-back. Pinny does
not turn a helper command's exit code into pinned state without verification.

### `yabai-msg: failed to connect to socket..`

The executable exists but its user service is not running. `yabai
--start-service` is the upstream command. Starting the service alone still does
not enable layer control without the separately configured scripting addition.

### A global shortcut does not respond

Check the popover for a registration error and quit any shortcut utility using
the same key. Pinny requests Control, not Command: `⌃Z` toggles pin, `⌃.`
hides, and `⌃,` restores. Also confirm Accessibility is enabled for the stable
app copy.

### A window stayed above after an error or crash

With yabai running, identify the window and relinquish its manual sub-layer:

```sh
yabai -m window <window-id> --sub-layer auto
```

Restarting the window's owning application also destroys the affected window.
See the manual test document before testing failure recovery.

### Launch at Login cannot find Pinny

Move the app to `/Applications`, launch that copy, and retry. Approve it in Login
Items if macOS requires approval.
