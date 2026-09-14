import AppKit
import Foundation

final class NotificationManager {
    private var panel: NSPanel?
    private var dismissalWorkItem: DispatchWorkItem?

    func show(message: String) {
        dismissalWorkItem?.cancel()
        panel?.close()

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let container: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            view.layer?.borderColor = NSColor.separatorColor.cgColor
            view.layer?.borderWidth = 1
            container = view
        } else {
            let effectView = NSVisualEffectView()
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            container = effectView
        }
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 13),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -13)
        ])

        let size = label.intrinsicContentSize
        let panelSize = NSSize(width: max(150, size.width + 44), height: 48)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.ignoresMouseEvents = true
        panel.alphaValue = 1

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? .main
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.maxY - panelSize.height - 36
            ))
        }

        panel.orderFrontRegardless()
        self.panel = panel

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.close()
            if self.panel === panel {
                self.panel = nil
            }
        }
        dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: workItem)
    }

    func cleanUp() {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
        panel?.close()
        panel = nil
    }
}
