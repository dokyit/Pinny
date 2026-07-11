import AppKit
import CoreGraphics
import Foundation

@main
struct RuntimeProbe {
    static func main() {
        let bundleIdentifier = CommandLine.arguments.dropFirst().first ?? "com.pinnyutility.Pinny"
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            fputs("No running application with bundle identifier \(bundleIdentifier).\n", stderr)
            exit(2)
        }

        let policy: String
        switch application.activationPolicy {
        case .regular: policy = "regular"
        case .accessory: policy = "accessory"
        case .prohibited: policy = "prohibited"
        @unknown default: policy = "unknown"
        }

        let allWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let ownedWindows = allWindows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int) == Int(application.processIdentifier)
        }

        print("Bundle identifier: \(bundleIdentifier)")
        print("PID: \(application.processIdentifier)")
        print("Activation policy: \(policy)")
        print("Active: \(application.isActive)")
        print("Hidden: \(application.isHidden)")
        print("On-screen windows owned by Pinny: \(ownedWindows.count)")
        for window in ownedWindows {
            let layer = window[kCGWindowLayer as String] ?? "unknown"
            let name = window[kCGWindowName as String] ?? "untitled"
            let bounds = window[kCGWindowBounds as String] ?? [:]
            print("- layer \(layer), name \(name), bounds \(bounds)")
        }
    }
}
