import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    let actions: MenuBarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                Image(systemName: model.hasPinnedWindow ? "pin.fill" : "pin")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(model.hasPinnedWindow ? Color.accentColor : Color.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pinny")
                        .font(.headline)
                    Text(model.menuPresentation.statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let detail = model.menuPresentation.statusDetail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Label("Advanced window-level backend", systemImage: "exclamationmark.shield")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Universal pinning requires a separately configured yabai Dock helper. It is unsupported by Apple and may break after macOS updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Setup and security details", action: actions.openAdvancedSetupGuide)
                    .font(.caption)
                    .buttonStyle(.link)
            }
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.55), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !model.isAccessibilityTrusted {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Pinny needs Accessibility permission to identify the focused window and route it to the configured window-level helper.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Request Permission", action: actions.requestAccessibility)
                            .buttonStyle(.borderedProminent)
                        Button("Open Settings", action: actions.openAccessibilitySettings)
                    }
                }
                .padding(11)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            Button(action: actions.toggleCurrentWindow) {
                HStack {
                    Text(model.menuPresentation.actionTitle)
                    Spacer()
                    Text(model.shortcutDisplayName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.menuPresentation.canToggleWindow)

            HStack(spacing: 8) {
                Button(action: actions.hideCurrentWindow) {
                    HStack {
                        Text("Hide Current")
                            .foregroundStyle(Color(nsColor: .labelColor))
                        Spacer()
                        Text(HotKeyConfiguration.controlPeriod.displayName)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(!model.isAccessibilityTrusted)
                .opacity(model.isAccessibilityTrusted ? 1 : 0.55)

                Button(action: actions.showLastHiddenWindow) {
                    HStack {
                        Text("Restore Last")
                            .foregroundStyle(Color(nsColor: .labelColor))
                        Spacer()
                        Text(HotKeyConfiguration.controlComma.displayName)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(!model.isAccessibilityTrusted || !model.hasHiddenWindows)
                .opacity(model.isAccessibilityTrusted && model.hasHiddenWindows ? 1 : 0.55)
            }

            Button(action: actions.raiseCurrentWindowOnce) {
                Text("Raise Current Window Once (Fallback)")
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
                .buttonStyle(.plain)
                .disabled(!model.isAccessibilityTrusted)
                .opacity(model.isAccessibilityTrusted ? 1 : 0.55)

            Divider()

            Toggle("Launch at Login", isOn: Binding(
                get: { model.isLaunchAtLoginEnabled },
                set: actions.setLaunchAtLogin
            ))

            if let launchAtLoginMessage = model.launchAtLoginMessage {
                VStack(alignment: .leading, spacing: 5) {
                    Text(launchAtLoginMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: actions.openLoginItemsSettings) {
                        Text("Open Login Items Settings")
                            .foregroundStyle(Color.accentColor)
                    }
                        .font(.caption)
                        .buttonStyle(.plain)
                }
            }

            Divider()

            HStack {
                Button("About Pinny", action: actions.showAbout)
                    .buttonStyle(.plain)
                Spacer()
                Button("Quit Pinny", action: actions.quit)
                    .buttonStyle(.plain)
                    .keyboardShortcut("q")
            }
        }
        .padding(15)
        .frame(width: 340)
    }
}
