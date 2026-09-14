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
            hideCurrentWindow: {},
            showLastHiddenWindow: {},
            raiseCurrentWindowOnce: {},
            selectPreviewWindow: { _ in },
            requestAccessibility: {},
            openAccessibilitySettings: {},
            setLaunchAtLogin: { _ in },
            openLoginItemsSettings: {},
            showAbout: {},
            quit: {}
        )

        let previewWindow = PreviewWindow(
            id: 501,
            processIdentifier: 4242,
            applicationName: "Safari",
            title: "Documentation — Apple Developer",
            frame: CGRect(x: 40, y: 60, width: 1280, height: 800)
        )
        let choiceWindows = [
            previewWindow,
            PreviewWindow(
                id: 502,
                processIdentifier: 4243,
                applicationName: "Notes",
                title: nil,
                frame: CGRect(x: 0, y: 0, width: 700, height: 500)
            ),
            PreviewWindow(
                id: 503,
                processIdentifier: 4244,
                applicationName: "TextEdit",
                title: "scratch.txt",
                frame: CGRect(x: 0, y: 0, width: 600, height: 700)
            )
        ]

        let permissionModel = AppModel()
        permissionModel.isAccessibilityTrusted = false
        permissionModel.status = .accessibilityPermissionRequired
        try render(
            view: MenuBarView(model: permissionModel, actions: actions),
            to: outputDirectory.appendingPathComponent("permission-required.png")
        )
        try render(
            view: MenuBarView(model: permissionModel, actions: actions),
            to: outputDirectory.appendingPathComponent("permission-required-light.png"),
            appearance: .aqua
        )

        let readyModel = AppModel()
        readyModel.isAccessibilityTrusted = true
        try render(
            view: MenuBarView(model: readyModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-ready.png")
        )
        try render(
            view: MenuBarView(model: readyModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-ready-light.png"),
            appearance: .aqua
        )
        try render(
            view: MenuBarView(model: readyModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-ready-contrast.png"),
            appearance: .accessibilityHighContrastDarkAqua
        )

        let choosingModel = AppModel()
        choosingModel.isAccessibilityTrusted = true
        choosingModel.previewState = .choosing(choiceWindows)
        try render(
            view: MenuBarView(model: choosingModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-choosing.png")
        )
        try render(
            view: MenuBarView(model: choosingModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-choosing-light.png"),
            appearance: .aqua
        )

        let startingModel = AppModel()
        startingModel.isAccessibilityTrusted = true
        startingModel.previewState = .starting(previewWindow)
        try render(
            view: MenuBarView(model: startingModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-starting.png")
        )

        let activeModel = AppModel()
        activeModel.isAccessibilityTrusted = true
        activeModel.previewState = .active(previewWindow)
        try render(
            view: MenuBarView(model: activeModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-active.png")
        )
        try render(
            view: MenuBarView(model: activeModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-active-light.png"),
            appearance: .aqua
        )

        let failedModel = AppModel()
        failedModel.isAccessibilityTrusted = true
        failedModel.previewState = .failed(
            "Screen Recording permission is required. Enable Pinny in System Settings > Privacy & Security > Screen Recording, then try again."
        )
        try render(
            view: MenuBarView(model: failedModel, actions: actions),
            to: outputDirectory.appendingPathComponent("preview-failed.png")
        )

        let longErrorModel = AppModel()
        longErrorModel.isAccessibilityTrusted = true
        longErrorModel.previewState = .failed(
            "The window did not produce any preview frames. The source may be protected by content restrictions, suspended by the system, or minimized on another space. Restore the window and try again."
        )
        longErrorModel.shortcutRegistrationFailure = "⌃Z is already registered by another application."
        longErrorModel.launchAtLoginMessage = "Launch at Login needs approval in System Settings > General > Login Items."
        try render(
            view: MenuBarView(model: longErrorModel, actions: actions),
            to: outputDirectory.appendingPathComponent("maximum-error-content.png")
        )

        let raisedModel = AppModel()
        raisedModel.isAccessibilityTrusted = true
        raisedModel.status = .windowRaisedOnce(PinnedWindowSummary(
            applicationName: "Calculator",
            windowTitle: "Scientific"
        ))
        raisedModel.hiddenWindowCount = 1
        try render(
            view: MenuBarView(model: raisedModel, actions: actions),
            to: outputDirectory.appendingPathComponent("raised-fallback.png")
        )

        print("Rendered menu previews to \(outputDirectory.path)")
    }

    private static func render<V: View>(
        view: V,
        to url: URL,
        appearance: NSAppearance.Name = .darkAqua
    ) throws {
        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = NSAppearance(named: appearance)
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
