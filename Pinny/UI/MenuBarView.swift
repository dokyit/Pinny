import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    let actions: MenuBarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let detail = model.menuPresentation.statusDetail {
                detailText(detail, isError: isFailureStatus)
            }

            Text("Keep a live, view-only copy above other windows. Screen Recording permission is required.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.isAccessibilityTrusted {
                permissionSection
            }

            if case .choosing(let windows) = model.previewState {
                windowChoices(windows)
            }

            Button(action: actions.toggleCurrentWindow) {
                HStack {
                    Text(model.menuPresentation.actionTitle)
                    Spacer()
                    Text(model.shortcutDisplayName)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.menuPresentation.canToggleWindow)

            VStack(alignment: .leading, spacing: 8) {
                actionButton(
                    "Hide Current",
                    shortcut: HotKeyConfiguration.controlPeriod.displayName,
                    action: actions.hideCurrentWindow
                )
                .disabled(!model.isAccessibilityTrusted)

                actionButton(
                    "Restore Last",
                    shortcut: HotKeyConfiguration.controlComma.displayName,
                    action: actions.showLastHiddenWindow
                )
                .disabled(!model.isAccessibilityTrusted || !model.hasHiddenWindows)

                actionButton(
                    "Raise Once",
                    action: actions.raiseCurrentWindowOnce
                )
                .disabled(!model.isAccessibilityTrusted)
                .help("Raises the focused window once; it may be covered again.")
            }

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { model.isLaunchAtLoginEnabled },
                set: actions.setLaunchAtLogin
            ))

            if let launchAtLoginMessage = model.launchAtLoginMessage {
                VStack(alignment: .leading, spacing: 6) {
                    detailText(launchAtLoginMessage, isError: true)
                    Button("Open Login Items Settings", action: actions.openLoginItemsSettings)
                }
            }

            Divider()

            HStack {
                Button("About Pinny", action: actions.showAbout)
                Spacer()
                Button("Quit Pinny", action: actions.quit)
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.hasPreview ? "pin.fill" : "pin")
                .font(.title3)
                .foregroundStyle(model.hasPreview ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pinny")
                    .font(.headline)
                Text(model.menuPresentation.statusTitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var isFailureStatus: Bool {
        if case .failed = model.previewState {
            return true
        }
        switch model.status {
        case .unableToRaise, .unableToHide, .unableToShow,
             .unableToPin, .shortcutRegistrationFailed, .advancedHelperRequired:
            return true
        case .ready, .windowPinned, .windowRaisedOnce, .windowHidden,
             .windowShown, .accessibilityPermissionRequired:
            return false
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accessibility permission is optional: it lets Pinny pick the focused window automatically and is required for hide and restore.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Allow Accessibility", action: actions.requestAccessibility)
                    .buttonStyle(.borderedProminent)
                Button("Open Settings", action: actions.openAccessibilitySettings)
            }
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func windowChoices(_ windows: [PreviewWindow]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(windows) { window in
                    Button {
                        actions.selectPreviewWindow(window)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(window.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Window")
                                    .lineLimit(1)
                                Text(window.applicationName)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        "Preview \(window.summary.displayName)"
                    )
                }
            }
            .padding(1)
        }
        .frame(maxHeight: 220)
    }

    private func detailText(_ text: String, isError: Bool) -> some View {
        Group {
            if isError {
                Label(text, systemImage: "exclamationmark.triangle")
            } else {
                Text(text)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func actionButton(
        _ title: String,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }
}
