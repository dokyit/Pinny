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

        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        effectView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -22),
            label.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 13),
            label.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -13)
        ])

        let size = label.intrinsicContentSize
        let panelSize = NSSize(width: max(150, size.width + 44), height: 48)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effectView
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
        panel.alphaValue = 0

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? .main
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.maxY - panelSize.height - 36
            ))
        }

        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        let workItem = DispatchWorkItem { [weak self, weak panel] in
            guard let self, let panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.close()
                if self.panel === panel {
                    self.panel = nil
                }
            })
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
