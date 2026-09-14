# Pinny agent notes

## Environment

- Toolchain is Command Line Tools only (no Xcode); `xcode-select -p` → `/Library/Developer/CommandLineTools`.
- The repo lives in a synced Documents folder. The fileprovider daemon re-adds
  `com.apple.FinderInfo`/`com.apple.fileprovider.fpfs` xattrs to build outputs, which makes
  codesign fail with "resource fork, Finder information, or similar detritus not allowed".
  Build SwiftPM products outside the synced tree with `--scratch-path /tmp/pinny-spm-build`
  (or `xattr -rc` the product before signing).
- SwiftPM does not auto-resolve the swift-testing macro plugin from the CLT
  `usr/lib/swift/host/plugins/testing/` subdirectory. `swift test` needs:
  `-Xswiftc -load-plugin-library -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib`

## Verification commands (from repo root)

```sh
swift build --scratch-path /tmp/pinny-spm-build -Xswiftc -warnings-as-errors
swift test --scratch-path /tmp/pinny-spm-build \
  -Xswiftc -load-plugin-library \
  -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
./Scripts/render-menu-previews.sh   # renders menu PNGs to build/MenuPreviews
```

## Safety

- The live preview is view-only (ScreenCaptureKit + NSPanel); do not probe or record
  captured window contents. Accessibility is optional for preview selection but required
  for hide/restore/raise.
- The app identity is "Pinny": bundle ID `com.pinnyutility.Pinny`, bundle
  `Pinny.app`, stable install location `/Applications/Pinny.app`.
  The Swift module and executable stay `Pinny`; tests use `com.pinnyutility.PinnyTests`.
- `Scripts/build-local.sh` runs `rm -rf` on `$PINNY_BUILD_ROOT/Pinny.app` — do not run
  it against an existing app output without approval; set `PINNY_BUILD_ROOT` to a fresh
  path (e.g. `/tmp/pinny-build-<n>`) instead.
- Legacy yabai/private-API sources and probes remain on disk intentionally; do not run the
  old security-setup scripts.
