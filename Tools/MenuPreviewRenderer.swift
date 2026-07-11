import AppKit
import SwiftUI

@main
struct MenuPreviewRenderer {
    static func main() throws {
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/MenuPreviews")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let actions = MenuBarActions(
            refreshState: {},
            toggleCurrentWindow: {},
            raiseCurrentWindowOnce: {},
            requestAccessibility: {},
            openAccessibilitySettings: {},
            setLaunchAtLogin: { _ in },
            openLoginItemsSettings: {},
            openAdvancedSetupGuide: {},
            showAbout: {},
            quit: {}
        )

        let permissionModel = AppModel()
        permissionModel.isAccessibilityTrusted = false
        permissionModel.status = .accessibilityPermissionRequired
        try render(
            view: MenuBarView(model: permissionModel, actions: actions),
            to: outputDirectory.appendingPathComponent("permission-required.png")
        )

        let errorModel = AppModel()
        errorModel.isAccessibilityTrusted = true
        errorModel.status = .unableToRaise("The selected application does not expose the AXRaise fallback action.")
        errorModel.shortcutRegistrationFailure = "⌃Z is already registered by another application."
        errorModel.launchAtLoginMessage = "Launch at Login needs approval in System Settings > General > Login Items."
        try render(
            view: MenuBarView(model: errorModel, actions: actions),
            to: outputDirectory.appendingPathComponent("maximum-error-content.png")
        )

        let raisedModel = AppModel()
        raisedModel.isAccessibilityTrusted = true
        raisedModel.status = .windowRaisedOnce(PinnedWindowSummary(
            applicationName: "Calculator",
            windowTitle: "Scientific"
        ))
        try render(
            view: MenuBarView(model: raisedModel, actions: actions),
            to: outputDirectory.appendingPathComponent("raised-fallback.png")
        )

        print("Rendered menu previews to \(outputDirectory.path)")
    }

    private static func render<V: View>(view: V, to url: URL) throws {
        let hostingView = NSHostingView(rootView: view)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(340, fittingSize.width),
            height: fittingSize.height
        )
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw NSError(domain: "PinnyMenuPreview", code: 1)
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PinnyMenuPreview", code: 2)
        }
        try data.write(to: url, options: .atomic)
    }
}
