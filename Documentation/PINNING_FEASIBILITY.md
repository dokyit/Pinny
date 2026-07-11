# Third-Party Window Pinning Feasibility

Last updated: July 10, 2026

## Decision

An ordinary macOS process cannot generically make one window owned by another
application persistently always-on-top.

- Public AppKit changes only windows owned by the caller.
- Public Accessibility can identify, move, resize, minimize, focus, and request
  `AXRaise`, but it has no writable foreign-window-level attribute.
- Public Core Graphics window-list APIs observe level and ordering; they do not
  mutate them.
- Dynamically loaded private CGS/SLS setters were not a usable escape hatch on
  macOS 26.5.2. They returned values that looked successful while WindowServer's
  independent presentation state and cross-application z-order did not change.

Pinny therefore has two honest operating paths:

1. **Optional persistent backend:** send a narrowly scoped `--sub-layer`
   command to a user-installed yabai service whose scripting addition runs in
   Dock and has the WindowServer presenter authority Pinny lacks.
2. **Public fallback:** expose a separately labeled one-shot `AXRaise` action.
   It is not a pin, and controlled testing showed no cross-app effect while a
   different application remained frontmost.

The yabai route is technically plausible and implemented, but it is not a
normal-permission solution. It requires explicit, security-reducing setup by
the Mac's owner. Pinny never installs or starts yabai, changes System Integrity
Protection, writes NVRAM, edits sudoers, or injects code into Dock.

## Public API boundary

### Accessibility

An Accessibility client can create an application element for a PID, retrieve
`kAXFocusedWindowAttribute`, inspect the window role/title, and use supported
attributes and actions. This is sufficient to select one specific window rather
than every window in an application.

The relevant public capabilities include:

- `kAXPositionAttribute` and `kAXSizeAttribute`;
- `kAXMinimizedAttribute`;
- `kAXMainAttribute` and `kAXFocusedAttribute`, when supported; and
- `kAXRaiseAction`.

None of these is a persistent compositor level. Apple's description of
`kAXRaiseAction` is application-scoped: it makes a window as frontmost as its
containing application permits. It neither grants presenter rights nor changes
the owning application's WindowServer layer.

There is no public `kAXWindowLevelAttribute`. Querying the raw string
`"AXWindowLevel"` on tested windows returned
`kAXErrorAttributeUnsupported` (`-25205`) and not-settable.

The base app is unsandboxed because Apple documents cross-application AX clients
as incompatible with App Sandbox. Removing App Sandbox does not add a foreign
window-level API.

### AppKit and Core Graphics

`NSWindow.level` is effective only for an `NSWindow` the caller owns. Looking up
a third-party `CGWindowID` does not create an `NSWindow` proxy and does not
transfer ownership.

`CGWindowListCopyWindowInfo` exposes observational keys such as:

- `kCGWindowNumber`;
- `kCGWindowOwnerPID`;
- `kCGWindowLayer`;
- bounds, alpha, name, and sharing state.

Those values are valuable for independent verification, not mutation.
`CGWindowLevelForKey` maps a public level key to a numeric level for windows the
caller can legitimately configure; it does not grant authority over a foreign
window.

## Controlled local evidence

Validation ran on an arm64 Mac with macOS 26.5.2 build 25F84, macOS SDK 26.5,
and Apple Swift 6.3.3.

### Public AX inventory

Live foreign windows returned 28 AX attributes and exposed `AXRaise`, but no
window-level/always-on-top attribute. The raw `AXWindowLevel` settable query was
unsupported. This result was reproduced against ChatGPT/Codex-family windows and
an earlier Football Manager 26 target.

### Controlled `AXRaise` persistence test

`Tools/AXRaisePersistenceProbe.swift` created a normal foreground cover window
from a different application, held that app frontmost, and repeatedly invoked
`AXRaise` on the previously focused Codex window (CG window ID 1202). It sampled
independent `CGWindowListCopyWindowInfo` order after every action.

| Observation | Result |
| --- | --- |
| AX action results | 10/10 returned success |
| Target rank | Stayed 23 |
| Cover rank | Stayed 20 |
| Target above cover | 0/10 observations |
| Frontmost-app changes | 0 |

This is stronger than merely observing an unchanged numeric layer: the action
reported success but did not move the foreign target above the active window
from another application. Repeating `AXRaise` is therefore neither a reliable
pin nor a polling workaround.

### Private CGS/SLS false success

The installed private symbol surface includes `_AXUIElementGetWindow`,
`CGSMainConnectionID`, `CGSGetWindowLevel`, and `CGSSetWindowLevel`. Resolving a
symbol only proves its presence and ABI compatibility on this macOS build.

Two reversible experiments targeted ChatGPT/Codex windows whose transient IDs
were 1202 and 3077:

1. Map the exact AX element to a `CGWindowID` and verify the owner PID.
2. Record independent SLS iterator data, `kCGWindowLayer`, and cross-app z-order.
3. Call `CGSSetWindowLevel(connection, window, 3)`.
4. Read using both `CGSGetWindowLevel` and independent presentation sources.
5. Attempt restoration and repeat with selected connection/order variants.

`CGSSetWindowLevel` returned `0`, and `CGSGetWindowLevel` echoed level `3`.
Those two values initially looked like success. They were not sufficient:

- the SLS window iterator remained at normal presentation layer `0`;
- public `kCGWindowLayer` remained `0`;
- the target did not move above a foreground window from another app; and
- unified logging recorded that the calling connection lacked presenter rights.

Experiments involving owner/Dock numeric connection IDs, window groups,
sub-levels, transactions, and ordering variants either failed or produced the
same no-op. The private getter appears able to echo connection-local requested
state even when WindowServer refuses to present it. Production verification
must therefore never trust only a setter return code or its paired getter.

Direct CGS/SLS mutation was rejected as Pinny's production backend for three
independent reasons:

1. It had no visual/presentation effect on the tested system.
2. The symbols are private, unsupported, and can change without notice.
3. It would still not solve the missing presenter authority that WindowServer
   enforces.

Pinny uses the private `_AXUIElementGetWindow` only to map a selected AX element
to the numeric window ID yabai expects. Mapping does not itself mutate the
window. If that symbol disappears or fails, Pinny reports failure.

## Why yabai can be different

[yabai](https://github.com/asmvik/yabai) documents that its scripting addition
uses macOS Mach APIs to inject into Dock. Dock owns the privileged connection
needed for WindowServer features that ordinary clients cannot perform. Upstream
explicitly lists window-layer control among the features requiring the scripting
addition and partial SIP disablement.

Pinny invokes only yabai's message interface:

```sh
yabai -m query --windows --window <window-id>
yabai -m window <window-id> --sub-layer above
yabai -m window <window-id> --sub-layer <recorded-original>
```

The [current yabai command reference](https://github.com/asmvik/yabai/blob/master/doc/yabai.asciidoc)
defines `LAYER` as `below | normal | above | auto` and documents
`--sub-layer <LAYER>` as the current window command. `auto` relinquishes manual
sub-layer control. The older `--layer` spelling must not be used.

The helper remains optional and independently managed. Pinny does not link to,
bundle, update, privilege, or inject yabai.

## Security prerequisites for Apple Silicon Tahoe

The authoritative upstream pages are:

- [Disabling System Integrity Protection](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection)
- [Installing yabai (latest release)](https://github.com/asmvik/yabai/wiki/Installing-yabai-%28latest-release%29)
- [Uninstalling yabai](https://github.com/asmvik/yabai/wiki/Uninstalling-yabai)

As reviewed July 10, 2026, upstream requires all of the following for layer
control on Apple Silicon macOS 13 or newer:

1. Boot to RecoveryOS.
2. Partially disable filesystem, debugging, and NVRAM protections:

   ```sh
   csrutil enable --without fs --without debug --without nvram
   ```

3. Reboot, set the non-Apple-signed arm64e preview ABI boot argument, and reboot
   again:

   ```sh
   sudo nvram boot-args=-arm64e_preview_abi
   ```

4. Install and Accessibility-authorize yabai.
5. Create a checksum-pinned sudoers authorization for the root-only
   `yabai --load-sa` operation.
6. Load the scripting addition and configure its reload after Dock restarts.

These actions deliberately reduce platform protections. The boot-argument
command can overwrite an existing value, and the scripting addition is
administrative code injection into a system process. Managed or corporate Macs
may prohibit the setup. A user must make this decision outside Pinny.

### Live advanced-backend result

The validation Mac was explicitly configured according to upstream yabai
requirements. yabai v7.1.25, its user service, checksum-restricted sudo rule,
and Dock scripting addition were installed and verified live. A reversible
ChatGPT test observed `sub-layer normal (0) → above (3) → normal (0)`.

The setup also exposed an important ordering requirement: the yabai daemon must
be running before its Dock payload is loaded. Restarting the daemon after
injection strands the payload on a dead socket. The included setup script now
starts the daemon first and verifies a live no-op sub-layer command rather than
mistaking files on disk for an active payload.

Nothing in Pinny automatically advances the security setup; it remains an
explicit administrator decision.

## Backend safety contract

The implementation treats yabai as a privileged, fallible external actor. A
zero exit status alone is not success.

### Pin

1. Resolve one focused AX element to one window ID.
2. Query yabai for the ID, owner PID, and current sub-layer.
3. Require the queried PID to equal the focused AX application's PID.
4. Accept only a known restorable original layer (`below`, `normal`, `above`).
5. Record PID, ID, and original sub-layer in a process-local token.
6. Request `above`.
7. Query again and require the same PID and an observed `above` sub-layer before
   entering pinned state.
8. If verification fails, attempt immediate restoration and report failure.

### Maintain

Once per second, Pinny queries the recorded ID. If the same owner is present but
the sub-layer drifted, it re-applies and re-verifies `above`. A transient helper
error retains state. If the target disappeared or the ID now belongs to a
different PID, Pinny clears the stale target and never mutates the new owner.

### Unpin and quit

Pinny restores the exact recorded original sub-layer, verifies the same owner
and read-back, and retries once. It also attempts restoration when replacing the
pinned window and during normal quit. A disappeared target is already restored
in the practical sense because the window no longer exists.

No process can guarantee restoration after its own force-kill, a Dock/yabai
crash, a power loss, or a macOS bug. Manual recovery is:

```sh
yabai -m window <window-id> --sub-layer auto
```

or quitting/restarting the target application.

## Unsupported alternatives

- **Treat `AXRaise` as pinning:** rejected by the controlled cross-app test.
- **Poll `AXRaise`:** rejected; it steals resources, can disrupt focus, and the
  same test showed no cross-app effect even with repetition.
- **Set `NSWindow.level` on a foreign window:** impossible; no foreign
  `NSWindow` object exists in Pinny.
- **Trust direct CGS/SLS return codes:** rejected by the verified false-success
  case.
- **Inject Pinny itself into every target:** rejected for safety, maintenance,
  code-signing, and distribution reasons.
- **Pretend Accessibility permission grants presenter rights:** false; AX trust
  and WindowServer presentation authority are distinct.

## User-facing truthfulness requirements

Pinny must:

- display `Pinned` only after yabai read-back confirms the selected ID, owner,
  and `above` sub-layer;
- retain truthful pinned state when restoration temporarily fails;
- call the public action **Raise Current Window Once (Fallback)**, never pin;
- identify the optional backend as advanced, privileged, unsupported by Apple,
  and liable to break after macOS updates;
- explain when yabai is missing, stopped, or not ready; and
- never imply that installing Pinny alone weakens or configures the Mac.

## Primary references

### yabai

- [Primary repository and requirements](https://github.com/asmvik/yabai)
- [Current rendered command source](https://github.com/asmvik/yabai/blob/master/doc/yabai.asciidoc)
- [Latest-release installation and scripting addition](https://github.com/asmvik/yabai/wiki/Installing-yabai-%28latest-release%29)
- [SIP requirements for privileged features](https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection)
- [Uninstall instructions](https://github.com/asmvik/yabai/wiki/Uninstalling-yabai)

### Apple

- [`AXUIElement`](https://developer.apple.com/documentation/applicationservices/axuielement)
- [`AXUIElementPerformAction`](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction)
- [`kAXRaiseAction`](https://developer.apple.com/documentation/applicationservices/kaxraiseaction)
- [`NSWindow.Level`](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct)
- [`CGWindowListCopyWindowInfo`](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo)
- [`kCGWindowLayer`](https://developer.apple.com/documentation/coregraphics/kcgwindowlayer)
- [System Integrity Protection](https://support.apple.com/102149)

Apple does not document `_AXUIElementGetWindow`, CGS, or SLS as application
APIs. Their observed behavior is local experimental evidence, not a compatibility
contract.
