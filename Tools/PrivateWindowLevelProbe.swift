import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

private typealias AXGetWindowID = @convention(c) (
    AXUIElement,
    UnsafeMutablePointer<CGWindowID>
) -> AXError
private typealias CGSMainConnectionID = @convention(c) () -> Int32
private typealias CGSGetWindowLevel = @convention(c) (
    Int32,
    CGWindowID,
    UnsafeMutablePointer<Int32>
) -> CGError
private typealias CGSSetWindowLevel = @convention(c) (
    Int32,
    CGWindowID,
    Int32
) -> CGError

private enum ProbeError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case dynamicLoad(String)
    case missingSymbol(String)
    case accessibilityPermissionRequired
    case noFocusedApplication(AXError)
    case invalidFocusedApplication
    case ownProcess
    case refusedTarget(String)
    case noFocusedWindow(AXError)
    case invalidFocusedWindow
    case windowID(AXError)
    case missingWindowInfo(CGWindowID)
    case ownerMismatch(expected: pid_t, actual: pid_t)
    case getLevel(CGError)
    case setLevel(CGError)
    case verification(expected: Int32, actual: Int32?)
    case restoration(CGError)
    case restorationVerification(expected: Int32, actual: Int32?)

    var description: String {
        switch self {
        case .invalidArguments(let message):
            return "invalid arguments: \(message)"
        case .dynamicLoad(let message):
            return "dynamic loader error: \(message)"
        case .missingSymbol(let name):
            return "private symbol is unavailable: \(name)"
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required"
        case .noFocusedApplication(let error):
            return "no focused AX application (AXError \(error.rawValue))"
        case .invalidFocusedApplication:
            return "the focused AX application value is invalid"
        case .ownProcess:
            return "the focused application is the probe itself"
        case .refusedTarget(let message):
            return message
        case .noFocusedWindow(let error):
            return "no focused AX window (AXError \(error.rawValue))"
        case .invalidFocusedWindow:
            return "the focused AX window value is invalid"
        case .windowID(let error):
            return "_AXUIElementGetWindow failed (AXError \(error.rawValue))"
        case .missingWindowInfo(let windowID):
            return "CGWindowListCopyWindowInfo returned no record for window \(windowID)"
        case .ownerMismatch(let expected, let actual):
            return "CG window owner mismatch (expected PID \(expected), got \(actual))"
        case .getLevel(let error):
            return "CGSGetWindowLevel failed (CGError \(error.rawValue))"
        case .setLevel(let error):
            return "CGSSetWindowLevel failed (CGError \(error.rawValue))"
        case .verification(let expected, let actual):
            return "floating-level verification failed (expected \(expected), got \(actual.map(String.init) ?? "missing"))"
        case .restoration(let error):
            return "restoration failed (CGError \(error.rawValue))"
        case .restorationVerification(let expected, let actual):
            return "restoration verification failed (expected \(expected), got \(actual.map(String.init) ?? "missing"))"
        }
    }
}

private struct Options {
    enum Mode {
        case symbolCheck
        case live
    }

    let mode: Mode
    let duration: TimeInterval

    static func parse(_ arguments: ArraySlice<String>) throws -> Options {
        var mode: Mode = .symbolCheck
        var duration: TimeInterval = 2
        var index = arguments.startIndex

        while index < arguments.endIndex {
            switch arguments[index] {
            case "--symbol-check", "--dry-run":
                mode = .symbolCheck
                index = arguments.index(after: index)
            case "--live":
                mode = .live
                index = arguments.index(after: index)
            case "--duration":
                let valueIndex = arguments.index(after: index)
                guard valueIndex < arguments.endIndex,
                      let value = TimeInterval(arguments[valueIndex]),
                      value >= 0,
                      value <= 10 else {
                    throw ProbeError.invalidArguments("--duration must be between 0 and 10 seconds")
                }
                duration = value
                index = arguments.index(after: valueIndex)
            case "--help", "-h":
                printUsage()
                exit(EXIT_SUCCESS)
            default:
                throw ProbeError.invalidArguments("unknown option \(arguments[index])")
            }
        }

        return Options(mode: mode, duration: duration)
    }

    static func printUsage() {
        print("Usage: PrivateWindowLevelProbe [--symbol-check | --live] [--duration 0...10]")
        print("No mode defaults to --symbol-check. --live temporarily changes the focused foreign window.")
    }
}

private final class PrivateWindowSymbols {
    let getAXWindowID: AXGetWindowID
    let mainConnectionID: CGSMainConnectionID
    let getWindowLevel: CGSGetWindowLevel
    let setWindowLevel: CGSSetWindowLevel

    private let handles: [UnsafeMutableRawPointer]

    init() throws {
        let applicationServicesPath = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        let coreGraphicsPath = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        let applicationServices = try Self.open(applicationServicesPath)
        let coreGraphics = try Self.open(coreGraphicsPath)
        handles = [applicationServices, coreGraphics]

        getAXWindowID = try Self.resolve(
            "_AXUIElementGetWindow",
            from: applicationServices,
            as: AXGetWindowID.self
        )
        mainConnectionID = try Self.resolve(
            "CGSMainConnectionID",
            from: coreGraphics,
            as: CGSMainConnectionID.self
        )
        getWindowLevel = try Self.resolve(
            "CGSGetWindowLevel",
            from: coreGraphics,
            as: CGSGetWindowLevel.self
        )
        setWindowLevel = try Self.resolve(
            "CGSSetWindowLevel",
            from: coreGraphics,
            as: CGSSetWindowLevel.self
        )
    }

    deinit {
        for handle in handles.reversed() {
            dlclose(handle)
        }
    }

    private static func open(_ path: String) throws -> UnsafeMutableRawPointer {
        dlerror()
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw ProbeError.dynamicLoad(lastLoaderError() ?? "could not open \(path)")
        }
        return handle
    }

    private static func resolve<T>(
        _ name: String,
        from handle: UnsafeMutableRawPointer,
        as type: T.Type
    ) throws -> T {
        dlerror()
        guard let address = dlsym(handle, name) else {
            throw ProbeError.missingSymbol(name)
        }
        return unsafeBitCast(address, to: type)
    }

    private static func lastLoaderError() -> String? {
        guard let message = dlerror() else { return nil }
        return String(cString: message)
    }
}

private struct FocusedTarget {
    let application: NSRunningApplication
    let window: AXUIElement
    let title: String?
    let role: String?
    let windowID: CGWindowID
}

private struct WindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let layer: Int32
    let ownerName: String?
    let windowName: String?
}

@main
private struct PrivateWindowLevelProbe {
    static func main() {
        do {
            let options = try Options.parse(CommandLine.arguments.dropFirst())
            let symbols = try PrivateWindowSymbols()

            switch options.mode {
            case .symbolCheck:
                print("mode=symbol-check")
                print("symbol._AXUIElementGetWindow=resolved")
                print("symbol.CGSMainConnectionID=resolved")
                print("symbol.CGSGetWindowLevel=resolved")
                print("symbol.CGSSetWindowLevel=resolved")
                print("result=success")
            case .live:
                try runLive(symbols: symbols, duration: options.duration)
            }
        } catch {
            fputs("result=failure\n", stderr)
            fputs("error=\(String(reflecting: String(describing: error)))\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func runLive(
        symbols: PrivateWindowSymbols,
        duration: TimeInterval
    ) throws {
        guard AXIsProcessTrusted() else {
            throw ProbeError.accessibilityPermissionRequired
        }

        let target = try focusedTarget(getAXWindowID: symbols.getAXWindowID)
        let originalInfo = try windowInfo(windowID: target.windowID)
        guard originalInfo.ownerPID == target.application.processIdentifier else {
            throw ProbeError.ownerMismatch(
                expected: target.application.processIdentifier,
                actual: originalInfo.ownerPID
            )
        }

        let connectionID = symbols.mainConnectionID()
        var originalWindowLevel: Int32 = 0
        let getResult = symbols.getWindowLevel(
            connectionID,
            target.windowID,
            &originalWindowLevel
        )
        guard getResult == .success else {
            throw ProbeError.getLevel(getResult)
        }

        let floatingLevel = Int32(CGWindowLevelForKey(.floatingWindow))

        print("mode=live")
        print("duration.seconds=\(String(format: "%.3f", duration))")
        print("application.name=\(quoted(target.application.localizedName))")
        print("application.bundle_identifier=\(quoted(target.application.bundleIdentifier))")
        print("application.pid=\(target.application.processIdentifier)")
        print("window.title=\(quoted(target.title ?? originalInfo.windowName))")
        print("window.role=\(quoted(target.role))")
        print("window.cg_window_id=\(target.windowID)")
        print("window.original_cg_layer=\(originalInfo.layer)")
        print("window.original_cgs_level=\(originalWindowLevel)")
        print("window.requested_floating_level=\(floatingLevel)")

        var operationError: Error?
        var restorationError: Error?

        do {
            defer {
                print("restore.attempted=true")
                let restoreResult = symbols.setWindowLevel(
                    connectionID,
                    target.windowID,
                    originalWindowLevel
                )
                print("restore.cgs_result=\(restoreResult.rawValue)")

                if restoreResult != .success {
                    restorationError = ProbeError.restoration(restoreResult)
                } else {
                    let restoredLayer = waitForLayer(
                        windowID: target.windowID,
                        expected: originalInfo.layer,
                        timeout: 0.75
                    )
                    print("window.restored_cg_layer=\(optionalNumber(restoredLayer))")
                    let verified = restoredLayer == originalInfo.layer
                    print("restore.verified=\(verified)")
                    if !verified {
                        restorationError = ProbeError.restorationVerification(
                            expected: originalInfo.layer,
                            actual: restoredLayer
                        )
                    }
                }
            }

            do {
                let setResult = symbols.setWindowLevel(
                    connectionID,
                    target.windowID,
                    floatingLevel
                )
                print("set.cgs_result=\(setResult.rawValue)")
                guard setResult == .success else {
                    throw ProbeError.setLevel(setResult)
                }

                let pinnedLayer = waitForLayer(
                    windowID: target.windowID,
                    expected: floatingLevel,
                    timeout: 0.75
                )
                print("window.pinned_cg_layer=\(optionalNumber(pinnedLayer))")
                print("verify.layer_changed=\(pinnedLayer.map { $0 != originalInfo.layer } ?? false)")
                print("verify.floating_level=\(pinnedLayer == floatingLevel)")
                guard pinnedLayer == floatingLevel else {
                    throw ProbeError.verification(
                        expected: floatingLevel,
                        actual: pinnedLayer
                    )
                }

                if duration > 0 {
                    Thread.sleep(forTimeInterval: duration)
                }
            } catch {
                operationError = error
            }
        }

        if let operationError {
            throw operationError
        }
        if let restorationError {
            throw restorationError
        }
        print("result=success")
    }

    private static func focusedTarget(getAXWindowID: AXGetWindowID) throws -> FocusedTarget {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApplicationValue: CFTypeRef?
        let applicationResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApplicationValue
        )
        guard applicationResult == .success else {
            throw ProbeError.noFocusedApplication(applicationResult)
        }
        guard let focusedApplicationValue,
              CFGetTypeID(focusedApplicationValue) == AXUIElementGetTypeID() else {
            throw ProbeError.invalidFocusedApplication
        }

        let applicationElement = unsafeBitCast(focusedApplicationValue, to: AXUIElement.self)
        var pid: pid_t = 0
        guard AXUIElementGetPid(applicationElement, &pid) == .success,
              let application = NSRunningApplication(processIdentifier: pid) else {
            throw ProbeError.invalidFocusedApplication
        }
        guard pid != ProcessInfo.processInfo.processIdentifier else {
            throw ProbeError.ownProcess
        }
        try validate(application: application)

        var focusedWindowValue: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        guard windowResult == .success else {
            throw ProbeError.noFocusedWindow(windowResult)
        }
        guard let focusedWindowValue,
              CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID() else {
            throw ProbeError.invalidFocusedWindow
        }

        let window = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        var windowPID: pid_t = 0
        guard AXUIElementGetPid(window, &windowPID) == .success, windowPID == pid else {
            throw ProbeError.invalidFocusedWindow
        }

        let role = stringAttribute(kAXRoleAttribute as CFString, of: window)
        guard role == (kAXWindowRole as String) || role == (kAXSheetRole as String) else {
            throw ProbeError.refusedTarget("the focused AX element is not an application window")
        }

        var windowID = kCGNullWindowID
        let windowIDResult = getAXWindowID(window, &windowID)
        guard windowIDResult == .success, windowID != kCGNullWindowID else {
            throw ProbeError.windowID(windowIDResult)
        }

        return FocusedTarget(
            application: application,
            window: window,
            title: stringAttribute(kAXTitleAttribute as CFString, of: window),
            role: role,
            windowID: windowID
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
            "com.apple.systemuiserver",
            "com.apple.windowmanager"
        ]
        let blockedNames: Set<String> = [
            "control center",
            "dock",
            "notification center",
            "pinny",
            "systemuiserver",
            "windowmanager"
        ]

        if bundleIdentifier == "com.pinnyutility.pinny" || applicationName == "pinny" {
            throw ProbeError.refusedTarget("refusing to change a Pinny window")
        }
        if bundleIdentifier.map(blockedBundleIdentifiers.contains) == true
            || applicationName.map(blockedNames.contains) == true {
            throw ProbeError.refusedTarget("refusing to change protected macOS system UI")
        }
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func windowInfo(windowID: CGWindowID) throws -> WindowInfo {
        let records = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            windowID
        ) as? [[String: Any]] ?? []

        guard let record = records.first(where: {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
        }),
        let ownerPID = (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
        let layer = (record[kCGWindowLayer as String] as? NSNumber)?.int32Value else {
            throw ProbeError.missingWindowInfo(windowID)
        }

        return WindowInfo(
            windowID: windowID,
            ownerPID: ownerPID,
            layer: layer,
            ownerName: record[kCGWindowOwnerName as String] as? String,
            windowName: record[kCGWindowName as String] as? String
        )
    }

    private static func currentLayer(windowID: CGWindowID) -> Int32? {
        try? windowInfo(windowID: windowID).layer
    }

    private static func waitForLayer(
        windowID: CGWindowID,
        expected: Int32,
        timeout: TimeInterval
    ) -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        var observed = currentLayer(windowID: windowID)
        while observed != expected && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.025)
            observed = currentLayer(windowID: windowID)
        }
        return observed
    }

    private static func quoted(_ value: String?) -> String {
        value.map { String(reflecting: $0) } ?? "null"
    }

    private static func optionalNumber(_ value: Int32?) -> String {
        value.map(String.init) ?? "missing"
    }
}
