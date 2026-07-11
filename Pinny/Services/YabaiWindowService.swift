import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

struct YabaiWindowRecord: Equatable {
    let windowID: CGWindowID
    let ownerProcessIdentifier: pid_t
    let subLayer: String
}

protocol YabaiWindowServicing: AnyObject {
    func windowID(for element: AXUIElement) -> Result<CGWindowID, WindowPinningError>
    func windowRecord(for windowID: CGWindowID) -> Result<YabaiWindowRecord, WindowPinningError>
    func setSubLayer(_ subLayer: String, for windowID: CGWindowID) -> Result<Void, WindowPinningError>
}

struct YabaiCommandResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol YabaiCommandRunning {
    func run(executableURL: URL, arguments: [String]) -> Result<YabaiCommandResult, Error>
}

protocol PinningBackendReadinessChecking {
    func readinessIssue() -> String?
}

struct YabaiBackendReadinessChecker: PinningBackendReadinessChecking {
    private let executableURL: URL?
    private let runner: YabaiCommandRunning
    private let scriptingAdditionPath: String

    init(
        executableURL: URL? = YabaiWindowService.locateExecutable(),
        runner: YabaiCommandRunning = FoundationYabaiCommandRunner(),
        scriptingAdditionPath: String = "/Library/ScriptingAdditions/yabai.osax"
    ) {
        self.executableURL = executableURL
        self.runner = runner
        self.scriptingAdditionPath = scriptingAdditionPath
    }

    func readinessIssue() -> String? {
        guard let executableURL else {
            return "The optional yabai helper is not installed. See Setup and security details before enabling advanced mode."
        }
        guard FileManager.default.fileExists(atPath: scriptingAdditionPath) else {
            return "yabai is installed, but its privileged Dock scripting addition is not configured."
        }

        switch runner.run(
            executableURL: executableURL,
            arguments: ["-m", "query", "--displays"]
        ) {
        case .failure:
            return "The yabai service is not running."
        case .success(let result) where result.terminationStatus != 0:
            return "The yabai service is not running or is not accepting messages."
        case .success:
            return nil
        }
    }
}

struct FoundationYabaiCommandRunner: YabaiCommandRunning {
    func run(executableURL: URL, arguments: [String]) -> Result<YabaiCommandResult, Error> {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
            process.waitUntilExit()
            return .success(YabaiCommandResult(
                terminationStatus: process.terminationStatus,
                standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                standardError: standardError.fileHandleForReading.readDataToEndOfFile()
            ))
        } catch {
            return .failure(error)
        }
    }
}

/// A deliberately narrow client for yabai's message interface.
///
/// Changing a foreign window's compositor sub-layer requires presenter rights
/// that an ordinary macOS process does not have. A configured yabai scripting
/// addition performs only the sub-layer mutation from inside Dock, which owns
/// the privileged WindowServer connection. Pinny never installs or loads that
/// privileged component automatically.
final class YabaiWindowService: YabaiWindowServicing {
    private let executableURL: URL?
    private let runner: YabaiCommandRunning
    private let windowIDMapper: PrivateAXWindowIDMapper?
    private let mapperLoadFailure: String?

    init(
        executableURL: URL? = YabaiWindowService.locateExecutable(),
        runner: YabaiCommandRunning = FoundationYabaiCommandRunner()
    ) {
        self.executableURL = executableURL
        self.runner = runner

        do {
            windowIDMapper = try PrivateAXWindowIDMapper()
            mapperLoadFailure = nil
        } catch {
            windowIDMapper = nil
            mapperLoadFailure = error.localizedDescription
        }
    }

    func windowID(for element: AXUIElement) -> Result<CGWindowID, WindowPinningError> {
        guard let windowIDMapper else {
            return .failure(.advancedHelperUnavailable(
                mapperLoadFailure ?? "The WindowServer window mapper is unavailable on this macOS version."
            ))
        }
        return windowIDMapper.windowID(for: element)
    }

    func windowRecord(for windowID: CGWindowID) -> Result<YabaiWindowRecord, WindowPinningError> {
        switch run(arguments: ["-m", "query", "--windows", "--window", String(windowID)]) {
        case .failure(let error):
            return .failure(error)
        case .success(let command):
            guard command.terminationStatus == 0 else {
                return .failure(.advancedHelperUnavailable(Self.failureMessage(
                    command,
                    fallback: "The yabai service or its scripting addition is not ready."
                )))
            }

            do {
                let object = try JSONSerialization.jsonObject(with: command.standardOutput)
                guard let dictionary = object as? [String: Any],
                      let identifier = dictionary["id"] as? NSNumber,
                      let processIdentifier = dictionary["pid"] as? NSNumber,
                      let subLayer = dictionary["sub-layer"] as? String else {
                    return .failure(.advancedHelperUnavailable(
                        "yabai returned an unexpected window record."
                    ))
                }

                let record = YabaiWindowRecord(
                    windowID: identifier.uint32Value,
                    ownerProcessIdentifier: processIdentifier.int32Value,
                    subLayer: subLayer
                )
                guard record.windowID == windowID else {
                    return .failure(.staleWindow)
                }
                return .success(record)
            } catch {
                return .failure(.advancedHelperUnavailable(
                    "yabai returned invalid JSON while Pinny verified the target window."
                ))
            }
        }
    }

    func setSubLayer(
        _ subLayer: String,
        for windowID: CGWindowID
    ) -> Result<Void, WindowPinningError> {
        let allowedSubLayers: Set<String> = ["above", "normal", "below", "auto"]
        guard allowedSubLayers.contains(subLayer) else {
            return .failure(.targetRejected("Pinny refused an unknown window sub-layer."))
        }

        switch run(arguments: ["-m", "window", String(windowID), "--sub-layer", subLayer]) {
        case .failure(let error):
            return .failure(error)
        case .success(let command):
            guard command.terminationStatus == 0 else {
                return .failure(.advancedHelperUnavailable(Self.failureMessage(
                    command,
                    fallback: "yabai could not change this window's sub-layer. Its scripting addition may not be loaded."
                )))
            }
            return .success(())
        }
    }

    static func locateExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []
        if let override = environment["PINNY_YABAI_PATH"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/yabai",
            "/usr/local/bin/yabai"
        ])

        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map {
            URL(fileURLWithPath: $0)
        }
    }

    private func run(arguments: [String]) -> Result<YabaiCommandResult, WindowPinningError> {
        guard let executableURL else {
            return .failure(.advancedHelperUnavailable(
                "True generic pinning needs the optional yabai helper; Pinny did not find it in /opt/homebrew/bin or /usr/local/bin."
            ))
        }

        switch runner.run(executableURL: executableURL, arguments: arguments) {
        case .success(let result):
            return .success(result)
        case .failure(let error):
            return .failure(.advancedHelperUnavailable(
                "Pinny could not run yabai: \(error.localizedDescription)"
            ))
        }
    }

    private static func failureMessage(
        _ command: YabaiCommandResult,
        fallback: String
    ) -> String {
        let errorText = String(data: command.standardError, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outputText = String(data: command.standardOutput, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = [errorText, outputText].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.first
        return detail ?? fallback
    }
}

private final class PrivateAXWindowIDMapper {
    private typealias GetWindowID = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    private let handle: UnsafeMutableRawPointer
    private let getWindowID: GetWindowID

    init() throws {
        let path = "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        dlerror()
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw PrivateAXWindowIDMapperError.dynamicLoad(Self.lastLoaderError() ?? path)
        }
        self.handle = handle

        dlerror()
        guard let address = dlsym(handle, "_AXUIElementGetWindow") else {
            dlclose(handle)
            throw PrivateAXWindowIDMapperError.missingSymbol
        }
        getWindowID = unsafeBitCast(address, to: GetWindowID.self)
    }

    deinit {
        dlclose(handle)
    }

    func windowID(for element: AXUIElement) -> Result<CGWindowID, WindowPinningError> {
        var windowID = kCGNullWindowID
        let error = getWindowID(element, &windowID)
        guard error == .success, windowID != kCGNullWindowID else {
            return .failure(.windowIDMappingFailed(error))
        }
        return .success(windowID)
    }

    private static func lastLoaderError() -> String? {
        guard let message = dlerror() else { return nil }
        return String(cString: message)
    }
}

private enum PrivateAXWindowIDMapperError: LocalizedError {
    case dynamicLoad(String)
    case missingSymbol

    var errorDescription: String? {
        switch self {
        case .dynamicLoad(let reason):
            return "ApplicationServices could not be loaded: \(reason)"
        case .missingSymbol:
            return "The private AX-to-WindowServer mapping symbol is unavailable."
        }
    }
}
