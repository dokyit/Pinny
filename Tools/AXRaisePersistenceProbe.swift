import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case accessibilityPermissionRequired
    case noFrontmostApplication
    case ownProcess
    case noFocusedWindow(AXError)
    case invalidFocusedWindow
    case refusedTarget(String)
    case missingWindowIDSymbol
    case windowID(AXError)
    case missingWindowInfo(CGWindowID)
    case couldNotActivateCover
    case coverWindowMissing

    var description: String {
        switch self {
        case .invalidArguments(let message):
            return "invalid arguments: \(message)"
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required"
        case .noFrontmostApplication:
            return "there is no frontmost application"
        case .ownProcess:
            return "the probe became frontmost before it captured a foreign window"
        case .noFocusedWindow(let error):
            return "the frontmost application has no focused AX window (AXError \(error.rawValue))"
        case .invalidFocusedWindow:
            return "the focused AX value is not an application window"
        case .refusedTarget(let message):
            return message
        case .missingWindowIDSymbol:
            return "private symbol _AXUIElementGetWindow is unavailable"
        case .windowID(let error):
            return "_AXUIElementGetWindow failed (AXError \(error.rawValue))"
        case .missingWindowInfo(let windowID):
            return "CGWindowListCopyWindowInfo returned no record for window \(windowID)"
        case .couldNotActivateCover:
            return "the temporary cover app could not become frontmost"
        case .coverWindowMissing:
            return "the temporary cover window did not appear in CGWindowList"
        }
    }
}

private struct Options {
    enum Mode {
        case check
        case live
    }

    let mode: Mode
    let iterations: Int
    let interval: TimeInterval

    static func parse(_ arguments: ArraySlice<String>) throws -> Options {
        var mode: Mode = .check
        var iterations = 10
        var interval: TimeInterval = 0.2
        var index = arguments.startIndex

        while index < arguments.endIndex {
            switch arguments[index] {
            case "--check", "--dry-run":
                mode = .check
                index = arguments.index(after: index)
            case "--live":
                mode = .live
                index = arguments.index(after: index)
            case "--iterations":
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex,
                      let value = Int(arguments[valueIndex]),
                      (1...50).contains(value) else {
                    throw ProbeError.invalidArguments("--iterations must be between 1 and 50")
                }
                iterations = value
                index = arguments.index(after: valueIndex)
            case "--interval":
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex,
                      let value = TimeInterval(arguments[valueIndex]),
                      value >= 0.05,
                      value <= 2 else {
                    throw ProbeError.invalidArguments("--interval must be between 0.05 and 2 seconds")
                }
                interval = value
                index = arguments.index(after: valueIndex)
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw ProbeError.invalidArguments("unknown option \(arguments[index])")
            }
        }

        return Options(mode: mode, iterations: iterations, interval: interval)
    }

    static func printUsage() {
        print("Usage: AXRaisePersistenceProbe [--check | --live] [--iterations 1...50] [--interval 0.05...2]")
        print("No mode defaults to --check. --live temporarily places a probe window above the focused foreign window.")
    }
}

private typealias AXGetWindowID = @convention(c) (
    AXUIElement,
    UnsafeMutablePointer<CGWindowID>
) -> AXError

private final class AXWindowIDResolver {
    let resolve: AXGetWindowID
    private let handle: UnsafeMutableRawPointer

    init() throws {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw ProbeError.missingWindowIDSymbol
        }
        self.handle = handle

        guard let address = dlsym(handle, "_AXUIElementGetWindow") else {
            dlclose(handle)
            throw ProbeError.missingWindowIDSymbol
        }
        resolve = unsafeBitCast(address, to: AXGetWindowID.self)
    }

    deinit {
        dlclose(handle)
    }
}

private struct Target {
    let application: NSRunningApplication
    let window: AXUIElement
    let windowID: CGWindowID
    let title: String?
    let bounds: CGRect
}

private struct WindowRecord {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String?
    let title: String?
    let layer: Int32
    let bounds: CGRect
}

private struct Snapshot {
    let frontmostPID: pid_t?
    let frontmostName: String?
    let frontmostBundleIdentifier: String?
    let targetRank: Int?
    let coverRank: Int?
    let targetNormalRank: Int?
    let coverNormalRank: Int?

    var targetIsAboveCover: Bool? {
        guard let targetRank, let coverRank else { return nil }
        return targetRank < coverRank
    }
}

@main
private struct AXRaisePersistenceProbe {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments.dropFirst())
            print("mode=\(options.mode == .check ? "check" : "live")")
            print("accessibility.trusted=\(AXIsProcessTrusted())")

            guard options.mode == .live else {
                print("result=success")
                return
            }

            try runLive(options: options)
            print("result=success")
        } catch {
            fputs("result=failure\n", stderr)
            fputs("error=\(String(reflecting: String(describing: error)))\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func runLive(options: Options) throws {
        guard AXIsProcessTrusted() else {
            throw ProbeError.accessibilityPermissionRequired
        }

        let resolver = try AXWindowIDResolver()
        let target = try focusedTarget(using: resolver)

        print("target.application.name=\(quoted(target.application.localizedName))")
        print("target.application.bundle_identifier=\(quoted(target.application.bundleIdentifier))")
        print("target.application.pid=\(target.application.processIdentifier)")
        print("target.window.title=\(quoted(target.title))")
        print("target.window.cg_window_id=\(target.windowID)")
        print("iterations=\(options.iterations)")
        print("interval.seconds=\(String(format: "%.3f", options.interval))")

        let initial = snapshot(targetWindowID: target.windowID, coverWindowID: nil)
        printSnapshot(initial, prefix: "initial")

        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.finishLaunching()

        let coverWindow = makeCoverWindow(over: target.bounds)
        let originalApplication = target.application
        var restorationAttempted = false

        defer {
            print("cleanup.stop_repeating=true")
            coverWindow.orderOut(nil)
            coverWindow.close()
            application.setActivationPolicy(.prohibited)

            restorationAttempted = originalApplication.activate(options: [.activateAllWindows])
            pumpRunLoop(for: 0.45)

            let restored = snapshot(targetWindowID: target.windowID, coverWindowID: nil)
            print("cleanup.reactivate_attempted=true")
            print("cleanup.reactivate_accepted=\(restorationAttempted)")
            printSnapshot(restored, prefix: "cleanup")
            print("cleanup.original_frontmost_restored=\(restored.frontmostPID == originalApplication.processIdentifier)")
        }

        coverWindow.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        pumpRunLoop(for: 0.45)

        let coverWindowID = CGWindowID(coverWindow.windowNumber)
        guard coverWindowID != kCGNullWindowID else {
            throw ProbeError.coverWindowMissing
        }

        let covered = snapshot(targetWindowID: target.windowID, coverWindowID: coverWindowID)
        print("cover.window.cg_window_id=\(coverWindowID)")
        printSnapshot(covered, prefix: "covered")

        guard covered.frontmostPID == ProcessInfo.processInfo.processIdentifier else {
            throw ProbeError.couldNotActivateCover
        }
        guard covered.coverRank != nil else {
            throw ProbeError.coverWindowMissing
        }

        var successfulActions = 0
        var focusChanges = 0
        var targetAboveCoverObservations = 0
        var rankImprovements = 0

        for iteration in 1...options.iterations {
            let before = snapshot(targetWindowID: target.windowID, coverWindowID: coverWindowID)
            let actionResult = AXUIElementPerformAction(
                target.window,
                kAXRaiseAction as CFString
            )
            pumpRunLoop(for: min(options.interval, 0.12))
            let after = snapshot(targetWindowID: target.windowID, coverWindowID: coverWindowID)

            if actionResult == .success {
                successfulActions += 1
            }
            if after.frontmostPID != before.frontmostPID {
                focusChanges += 1
            }
            if after.targetIsAboveCover == true {
                targetAboveCoverObservations += 1
            }
            if let beforeRank = before.targetRank,
               let afterRank = after.targetRank,
               afterRank < beforeRank {
                rankImprovements += 1
            }

            print("sample.\(iteration).ax_result=\(actionResult.rawValue)")
            print("sample.\(iteration).frontmost_before.pid=\(optionalNumber(before.frontmostPID))")
            print("sample.\(iteration).frontmost_after.pid=\(optionalNumber(after.frontmostPID))")
            print("sample.\(iteration).frontmost_changed=\(after.frontmostPID != before.frontmostPID)")
            print("sample.\(iteration).target_rank_before=\(optionalNumber(before.targetRank))")
            print("sample.\(iteration).target_rank_after=\(optionalNumber(after.targetRank))")
            print("sample.\(iteration).cover_rank_after=\(optionalNumber(after.coverRank))")
            print("sample.\(iteration).target_above_cover=\(optionalBool(after.targetIsAboveCover))")

            let remaining = options.interval - min(options.interval, 0.12)
            if remaining > 0 {
                pumpRunLoop(for: remaining)
            }
        }

        let final = snapshot(targetWindowID: target.windowID, coverWindowID: coverWindowID)
        printSnapshot(final, prefix: "final")
        print("summary.actions_successful=\(successfulActions)")
        print("summary.focus_changes=\(focusChanges)")
        print("summary.rank_improvements=\(rankImprovements)")
        print("summary.target_above_cover_observations=\(targetAboveCoverObservations)")
        print("summary.kept_probe_frontmost=\(final.frontmostPID == ProcessInfo.processInfo.processIdentifier)")
        print("summary.persistent_cross_app_topmost=\(targetAboveCoverObservations == options.iterations)")
    }

    private static func focusedTarget(using resolver: AXWindowIDResolver) throws -> Target {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw ProbeError.noFrontmostApplication
        }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw ProbeError.ownProcess
        }
        try validate(application: application)

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        guard focusedWindowResult == .success else {
            throw ProbeError.noFocusedWindow(focusedWindowResult)
        }
        guard let focusedWindowValue,
              CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID() else {
            throw ProbeError.invalidFocusedWindow
        }

        let window = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        let role = stringAttribute(kAXRoleAttribute as CFString, of: window)
        guard role == (kAXWindowRole as String) || role == (kAXSheetRole as String) else {
            throw ProbeError.invalidFocusedWindow
        }

        var windowID = kCGNullWindowID
        let windowIDResult = resolver.resolve(window, &windowID)
        guard windowIDResult == .success, windowID != kCGNullWindowID else {
            throw ProbeError.windowID(windowIDResult)
        }

        let record = try windowRecord(windowID: windowID)
        guard record.ownerPID == application.processIdentifier else {
            throw ProbeError.missingWindowInfo(windowID)
        }
        guard record.layer == 0 else {
            throw ProbeError.refusedTarget(
                "refusing to test a nonstandard window layer (CG layer \(record.layer))"
            )
        }

        return Target(
            application: application,
            window: window,
            windowID: windowID,
            title: stringAttribute(kAXTitleAttribute as CFString, of: window) ?? record.title,
            bounds: record.bounds
        )
    }

    private static func validate(application: NSRunningApplication) throws {
        let bundleIdentifier = application.bundleIdentifier?.lowercased()
        let applicationName = application.localizedName?.lowercased()
        let blockedBundleIdentifiers: Set<String> = [
            "com.apple.controlcenter",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.notificationcenterui",
            "com.apple.securityagent",
            "com.apple.systemuiserver",
            "com.apple.windowmanager"
        ]
        let blockedNames: Set<String> = [
            "control center",
            "dock",
            "notification center",
            "pinny",
            "securityagent",
            "systemuiserver",
            "windowmanager"
        ]

        if bundleIdentifier == "com.pinnyutility.pinny" || applicationName == "pinny" {
            throw ProbeError.refusedTarget("refusing to test against a Pinny window")
        }
        if bundleIdentifier.map(blockedBundleIdentifiers.contains) == true
            || applicationName.map(blockedNames.contains) == true {
            throw ProbeError.refusedTarget("refusing to test against protected macOS system UI")
        }
    }

    private static func makeCoverWindow(over targetBounds: CGRect) -> NSWindow {
        let appKitTargetBounds = appKitRect(fromQuartzRect: targetBounds)
        let width = min(max(appKitTargetBounds.width * 0.62, 360), 720)
        let height = min(max(appKitTargetBounds.height * 0.52, 240), 520)
        var coverBounds = CGRect(
            x: appKitTargetBounds.midX - width / 2,
            y: appKitTargetBounds.midY - height / 2,
            width: width,
            height: height
        )

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(appKitTargetBounds) }) {
            coverBounds = coverBounds.intersection(screen.visibleFrame)
            if coverBounds.width < 240 || coverBounds.height < 160 {
                coverBounds = CGRect(
                    x: screen.visibleFrame.midX - 240,
                    y: screen.visibleFrame.midY - 140,
                    width: 480,
                    height: 280
                )
            }
        }

        let window = NSWindow(
            contentRect: coverBounds,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.level = .normal
        window.title = "AXRaise Persistence Probe — closes automatically"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: 0.96)

        let label = NSTextField(labelWithString: "Testing repeated Accessibility Raise…\nThis window closes automatically.")
        label.alignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(label)
        if let contentView = window.contentView {
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24)
            ])
        }
        return window
    }

    private static func appKitRect(fromQuartzRect rect: CGRect) -> CGRect {
        let mainScreenTop = NSScreen.screens.first?.frame.maxY ?? rect.maxY
        return CGRect(
            x: rect.minX,
            y: mainScreenTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func snapshot(
        targetWindowID: CGWindowID,
        coverWindowID: CGWindowID?
    ) -> Snapshot {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let records = windowRecords()
        let normalRecords = records.filter { $0.layer == 0 }

        return Snapshot(
            frontmostPID: frontmost?.processIdentifier,
            frontmostName: frontmost?.localizedName,
            frontmostBundleIdentifier: frontmost?.bundleIdentifier,
            targetRank: records.firstIndex { $0.windowID == targetWindowID },
            coverRank: coverWindowID.flatMap { id in records.firstIndex { $0.windowID == id } },
            targetNormalRank: normalRecords.firstIndex { $0.windowID == targetWindowID },
            coverNormalRank: coverWindowID.flatMap { id in normalRecords.firstIndex { $0.windowID == id } }
        )
    }

    private static func printSnapshot(_ value: Snapshot, prefix: String) {
        print("\(prefix).frontmost.pid=\(optionalNumber(value.frontmostPID))")
        print("\(prefix).frontmost.name=\(quoted(value.frontmostName))")
        print("\(prefix).frontmost.bundle_identifier=\(quoted(value.frontmostBundleIdentifier))")
        print("\(prefix).target_rank=\(optionalNumber(value.targetRank))")
        print("\(prefix).cover_rank=\(optionalNumber(value.coverRank))")
        print("\(prefix).target_normal_rank=\(optionalNumber(value.targetNormalRank))")
        print("\(prefix).cover_normal_rank=\(optionalNumber(value.coverNormalRank))")
        print("\(prefix).target_above_cover=\(optionalBool(value.targetIsAboveCover))")
    }

    private static func windowRecord(windowID: CGWindowID) throws -> WindowRecord {
        guard let record = windowRecords().first(where: { $0.windowID == windowID }) else {
            throw ProbeError.missingWindowInfo(windowID)
        }
        return record
    }

    private static func windowRecords() -> [WindowRecord] {
        let dictionaries = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return dictionaries.compactMap { dictionary in
            guard let windowID = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerPID = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.int32Value,
                  let boundsValue = dictionary[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary) else {
                return nil
            }

            return WindowRecord(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: dictionary[kCGWindowOwnerName as String] as? String,
                title: dictionary[kCGWindowName as String] as? String,
                layer: layer,
                bounds: bounds
            )
        }
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func pumpRunLoop(for duration: TimeInterval) {
        guard duration > 0 else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    private static func quoted(_ value: String?) -> String {
        value.map { String(reflecting: $0) } ?? "null"
    }

    private static func optionalNumber<T>(_ value: T?) -> String {
        value.map { String(describing: $0) } ?? "missing"
    }

    private static func optionalBool(_ value: Bool?) -> String {
        value.map(String.init) ?? "missing"
    }
}
