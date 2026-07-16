# Pinny Validation Report

Validation date: July 10, 2026

## Overall result

Pinny's native menu-bar application, focused-window selection, global shortcut
architecture, Accessibility onboarding, Launch at Login integration, feedback,
and one-window state model are implemented.

Persistent generic third-party pinning has a deliberately conditional result:

- **Public macOS only:** unavailable. AX and Core Graphics expose no writable
  foreign-window level, and controlled `AXRaise` testing produced no cross-app
  topmost effect.
- **Direct private CGS/SLS:** rejected. Set/get calls produced a false-success
  signal while independent WindowServer presentation and z-order stayed normal.
- **Optional yabai backend:** implemented around current `--sub-layer` commands,
  owner validation, read-back verification, maintenance, and exact restore. A
  live reversible ChatGPT test verified `normal (0) → above (3) → normal (0)`
  through the configured Dock scripting addition.

The app must not be described as universally functional on a stock Mac. The
advanced path works on the configured validation Mac, but Pinny never performs
the required security setup automatically.

## Evidence labels

This report uses three labels consistently:

- **Verified:** observed by a completed command, controlled probe, or direct
  inspection on this Mac.
- **Implemented, pending live validation:** present in source and reviewable, but
  the required external state was unavailable.
- **Not performed:** no result is claimed.

An API returning zero is not automatically classified as verified success. A
foreign-window mutation requires independent owner and presentation read-back.

## Validation environment

```text
Architecture:          arm64
macOS:                 26.5.2
Build:                 25F84
Developer directory:  /Library/Developer/CommandLineTools
macOS SDK:             26.5
Swift:                 Apple Swift 6.3.3
Full Xcode:            absent
```

Exact discovery commands:

```sh
uname -m
sw_vers
xcode-select -p
xcrun --sdk macosx --show-sdk-version
xcrun swift --version
xcodebuild -version
```

`xcodebuild -version` fails because the selected developer directory is the
standalone Command Line Tools installation. No Xcode scheme build, Xcode test,
asset-catalog compilation, archive, Developer ID signing, or notarization result
is claimed.

## Outcome matrix

| Area | Status | Evidence and boundary |
| --- | --- | --- |
| Native arm64 app and macOS 13 target | **Verified** | The settled source built with warnings as errors in debug and release. The optimized local bundle and mounted DMG copy passed arm64, plist, and ad-hoc hardened-runtime signature checks. |
| Menu-bar-only lifecycle | **Verified baseline** | A launched local bundle remained alive, Launch Services classified it as `UIElement`, activation policy was `accessory`, and the runtime probe found zero on-screen Pinny-owned normal windows. |
| Focused individual window | **Verified** | AX lookup and private ID mapping resolved individual foreign windows and matched their owner PIDs. `_AXUIElementGetWindow` is private and remains a compatibility risk. |
| Protected-target rejection | **Verified in tests/source; broader live matrix pending** | Pinny rejects itself and known Dock/menu bar/Control Center/Notification Center/login/security/desktop targets. |
| Global `⌃Z`, `⌃.`, and `⌃,` registration | **Implemented; live reservation verified, physical delivery pending** | A competing-process probe received Carbon `eventHotKeyExistsErr` for all three keys while Pinny 1.1.0 was running. Independent dispatch, failure reporting, and cleanup are covered; physical delivery while another app owns focus has not been recorded by the final automated harness. |
| Individual-window hide/restore | **Implemented** | AX minimized-state mutation is read back before success; hidden windows restore in LIFO order, stale targets are discarded, and transient failures retain retry state. |
| Public one-shot Raise | **Verified not to pin** | Controlled Codex test: 10/10 AX success, target rank 23, cover rank 20, 0/10 target-above-cover, no focus changes. |
| Direct CGS/SLS backend | **Rejected** | Private set/get echoed level 3 for tested window IDs, but SLS iterator, `kCGWindowLayer`, and cross-app z-order stayed at normal layer 0; presenter-right denial appeared in unified logging. |
| yabai executable | **Verified** | `/opt/homebrew/bin/yabai`, `yabai-v7.1.25`. |
| yabai service/socket | **Verified** | yabai v7.1.25 service is running with a float-only configuration and accepts messages. |
| yabai scripting addition | **Verified** | The Dock payload is installed, live, and accepts no-op and real sub-layer commands; automatic initial/restart loading is configured. |
| Pin via yabai | **Verified backend path** | A focused ChatGPT window changed from sub-layer `normal (0)` to `above (3)` with independent query read-back. |
| Unpin/restore via yabai | **Verified backend path** | The same live window restored from `above (3)` to its exact original `normal (0)` state. Owner/retry variants are covered by tests. |
| Drift maintenance | **Implemented and tested** | One-second maintenance re-applies `above` only to the recorded ID/owner; fake-service drift and transient failures are covered by the executable suite. |
| Accessibility onboarding | **Implemented; final installed-copy walkthrough pending** | Trust checks, prompt, Settings link, rechecks, and graceful failure exist. The stable `/Applications` copy must be tested after final build/signing. |
| Launch at Login | **Implemented; login-cycle test pending** | Uses `SMAppService.mainApp`, reads actual state, handles approval/not-found errors, and opens Login Items settings. No final login cycle is claimed. |
| Menu/HUD/icons | **Partially verified** | Native preview states and source assets were inspected. Final live yabai-success/failure states, light/dark status icon transition, and HUD timing need hands-on testing. |
| Spaces/full screen/minimize | **Not performed** | No universal claim is made. `above` does not imply sticky-across-Spaces or visibility over native full-screen/system UI. |

## Public and private feasibility evidence

### Public AX probe

The live inventory found:

```text
AX attributes:                    28
Writable public window level:    none
Raw AXWindowLevel query:         -25205 (attribute unsupported)
AXRaise advertised:              yes
```

An earlier Football Manager 26 probe returned AX success for `AXRaise` while
the reported CG layer remained `0`. The later controlled cover-window experiment
removed the ambiguity about visual ordering.

### Controlled AXRaise experiment

Target: Codex window, transient CG window ID 1202.

```text
AX actions successful:                 10 / 10
Target z-order rank:                   23 throughout
Probe cover z-order rank:              20 throughout
Target observed above cover:           0 / 10
Frontmost-application changes:         0
Persistent cross-app topmost:          false
```

The successful AX return code means the target accepted the action. It does not
mean WindowServer moved the target above the active window of another app.

The reusable tool is:

```sh
./Scripts/run-axraise-persistence-probe.sh --check
# --live creates and later closes a temporary foreground cover window.
```

The safe `--check` mode compiled, reported Accessibility trust, and exited
successfully. The exact live output above was recorded separately during the
controlled run.

### Direct private CGS/SLS experiment

The private symbol check succeeded:

```text
mode=symbol-check
symbol._AXUIElementGetWindow=resolved
symbol.CGSMainConnectionID=resolved
symbol.CGSGetWindowLevel=resolved
symbol.CGSSetWindowLevel=resolved
result=success
```

Against transient ChatGPT/Codex window IDs 1202 and 3077, the setter returned
`0` and its paired getter echoed floating level `3`. Independent observations
did not change:

```text
SLS iterator presentation layer:  0
kCGWindowLayer:                   0
Cross-app z-order:                unchanged
Unified log:                      presenter-right denial
```

Owner/Dock numeric connection IDs, group/sub-level calls, transactions, and
ordering variants were also explored and no-op'd or failed. Restoration was
attempted in the reversible probes. This evidence supersedes any earlier
interpretation that setter/getter agreement alone proved a real pin.

## yabai and security state

The final configured validation state produced:

```text
$ command -v yabai
/opt/homebrew/bin/yabai

$ yabai --version
yabai-v7.1.25

$ yabai -m query --displays
<successful display JSON>

$ ./Scripts/check-yabai-backend.sh
PASS  live Dock scripting addition accepts sub-layer commands
READY Pinny can attempt a verified window sub-layer change.
```

`csrutil status` reports `unknown (Custom Configuration)`, with the filesystem,
debugging, NVRAM, and boot-argument restrictions disabled as required by
upstream yabai. `nvram boot-args` contains `-arm64e_preview_abi`. The user
service, checksum-pinned sudoers rule, and Dock scripting addition are active.

### Actions performed versus not performed

| Action | Status |
| --- | --- |
| Install yabai v7.1.25 with Homebrew | **Performed** |
| Start yabai service | **Performed** |
| Grant yabai Accessibility permission | **Performed by user** |
| Change the existing SIP configuration | **Performed by user in RecoveryOS** |
| Disable NVRAM/boot-argument restrictions | **Performed by user in RecoveryOS** |
| Set `-arm64e_preview_abi` | **Performed by user** |
| Create `/private/etc/sudoers.d/yabai` | **Performed by setup script with checksum restriction** |
| Run `sudo yabai --load-sa` / inject Dock | **Performed and live-verified** |
| Set and restore a real yabai sub-layer | **Performed: `normal 0 → above 3 → normal 0`** |

The administrator explicitly performed or authorized the security-changing
steps. Pinny itself does not perform them during normal application operation.

## Optional backend implementation review

The production controller uses the current yabai interface:

```text
yabai -m query --windows --window <id>
yabai -m window <id> --sub-layer above
yabai -m window <id> --sub-layer <recorded-original>
```

The following safety properties are present in source:

1. The target comes from the focused AX window, not an application-wide rule.
2. The AX-derived numeric ID must query successfully in yabai.
3. Queried owner PID must match the focused application's PID.
4. Only known sub-layer values are accepted.
5. Success state requires a second query showing the same owner and `above`.
6. A new target cannot be pinned until the previous target restores.
7. Unpin and normal quit restore the exact recorded original value and verify
   it, with one retry.
8. Maintenance can re-apply a drifted `above` state.
9. A recycled ID is never mutated after an owner mismatch.
10. Transient maintenance/restore errors are reported without inventing success.

Remaining risks are inherent to the design: private AX-to-ID mapping can break,
yabai/Dock can crash or change behavior, a force-killed Pinny cannot run cleanup,
and a failed post-mutation rollback can leave manual recovery necessary.

## Build and automated-test ledger

### Verified baseline before advanced-backend integration

The prior public-only baseline recorded:

```text
swift build -c debug:       passed
swift build -c release:     passed
run-core-tests.sh:          25 passed, 0 failed
build-local.sh:             passed
bundle architecture:        arm64
bundle signature:           valid ad-hoc hardened-runtime signature
runtime activation policy:  accessory
Launch Services type:       UIElement
```

That baseline remains evidence for the common app architecture. It is not by
itself proof that newly added yabai sources or behavior are release-ready.

### Current advanced-backend source

The settled integrated source passed debug and release Swift builds with
warnings treated as errors. `Scripts/run-core-tests.sh` executed **50 tests:
50 passed, 0 failed**, including hide/restore stack invariants and 18 dedicated
yabai/controller invariants. The
Swift Testing sources also compiled; the standalone Command Line Tools
environment did not execute them through XCTest.

`Scripts/create-dmg.sh` produced `dist/Pinny-1.1.0-arm64.dmg`. `hdiutil verify`
reported a valid checksum, and the mounted app passed `codesign --verify
--deep --strict`, plist lint, and arm64 architecture checks. SHA-256:
`c8cb5560dc186e10c8513c5e74e38cab15096bc27d1307103fab8fcf67eb7093`.

Full Xcode and Swift Testing execution remain unavailable with standalone
Command Line Tools. Compilation without an executed test summary is not counted
as an Xcode test pass.

## Manual testing performed

| Scenario | Status |
| --- | --- |
| Controlled AXRaise cross-app ordering | **Verified; failed to pin as expected** |
| Direct private CGS/SLS mutation and independent read-back | **Verified; false success/rejected** |
| yabai executable/version discovery | **Verified** |
| Pinny with stopped/missing yabai service | **Verified; popover reported the socket failure honestly** |
| Real yabai `above` pin | **Verified on ChatGPT through the production command path** |
| Exact real-window restore | **Verified: `above (3)` restored to `normal (0)`** |
| Two windows in one app | **Not performed live** |
| Target close/application quit while pinned | **Not performed live** |
| Helper/Dock restart and payload reload | **Verified; initial load and Dock-restart signal configured** |
| Minimize/restore | **Not performed live** |
| Multiple Spaces/displays/Stage Manager | **Not performed** |
| Native full screen | **Not performed** |
| Final Accessibility onboarding | **Not performed on installed final copy** |
| Launch at Login full cycle | **Not performed** |
| Physical global `⌃Z` routing | **Not performed on final integrated build** |

Use [MANUAL_TESTS.md](MANUAL_TESTS.md) for the acceptance procedure and evidence
to capture.

## Remaining manual acceptance criteria

The generic backend and normal-layer restoration are now live-verified. The
remaining work is broader compatibility testing: two windows from one app,
minimize/restore, target termination, multiple Spaces, native full screen,
already-`above`/`below` restoration, and a complete logout/login cycle.

## Known restrictions

- The optional route is unsupported by Apple and can break with a macOS or
  yabai update.
- Layer control requires a security posture many users and managed Macs should
  not adopt.
- `above` is not sticky across Spaces and does not override secure/system UI or
  every native full-screen presentation.
- Only one Pinny-controlled window is tracked at a time.
- Pin state is process-local and intentionally not restored after restart.
- Force-kill, power loss, or helper/Dock failure can prevent automatic restore;
  manual `--sub-layer auto` or application restart may be required.
- `_AXUIElementGetWindow` is private and may disappear or change ABI.
- Direct CGS/SLS setter/getter return values are not valid proof of presentation
  on the tested macOS build.
