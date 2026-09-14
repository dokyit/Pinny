import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

enum WindowPreviewError: LocalizedError {
    case screenRecordingPermissionRequired
    case shareableContentUnavailable(String)
    case windowUnavailable
    case firstFrameTimeout

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionRequired:
            return "Screen Recording permission is required. Enable Pinny in System Settings > Privacy & Security > Screen Recording, then try again."
        case .shareableContentUnavailable(let reason):
            return "Pinny could not list shareable windows. \(reason) If Screen Recording permission is off, enable Pinny in System Settings > Privacy & Security > Screen Recording, then try again."
        case .windowUnavailable:
            return "The selected window is no longer available."
        case .firstFrameTimeout:
            return "The window did not produce any preview frames."
        }
    }
}

@MainActor
final class ScreenCapturePreviewController: NSObject {
    private let ownProcessIdentifier: pid_t
    private let sampleQueue = DispatchQueue(
        label: "com.pinnyutility.Pinny.preview-sample-output"
    )
    private var shareableWindows: [CGWindowID: SCWindow] = [:]
    private var activeSession: Session?

    override init() {
        ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        super.init()
    }
}

extension ScreenCapturePreviewController: WindowPreviewCapturing {
    func availableWindows() async throws -> [PreviewWindow] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
        } catch {
            if CGPreflightScreenCaptureAccess() {
                throw WindowPreviewError.shareableContentUnavailable(
                    error.localizedDescription
                )
            }
            throw WindowPreviewError.screenRecordingPermissionRequired
        }
        try Task.checkCancellation()

        var shareable: [CGWindowID: SCWindow] = [:]
        var previews: [PreviewWindow] = []
        for source in content.windows {
            guard source.windowLayer == 0 else { continue }
            guard source.frame.width > 0, source.frame.height > 0 else { continue }
            guard let application = source.owningApplication,
                  application.processID != ownProcessIdentifier else {
                continue
            }
            let name = application.applicationName.isEmpty
                ? "Unknown Application"
                : application.applicationName
            guard UnsupportedWindowFilter.rejectionReason(
                bundleIdentifier: application.bundleIdentifier,
                applicationName: name,
                role: "AXWindow"
            ) == nil else { continue }

            let title = source.title?.isEmpty == true ? nil : source.title
            shareable[source.windowID] = source
            previews.append(PreviewWindow(
                id: source.windowID,
                processIdentifier: application.processID,
                applicationName: name,
                title: title,
                frame: source.frame
            ))
        }

        try Task.checkCancellation()
        shareableWindows = shareable
        return previews
    }

    func start(
        window: PreviewWindow,
        sessionID: UUID,
        onReady: @escaping () -> Void,
        onEnd: @escaping (String?) -> Void
    ) async throws {
        try Task.checkCancellation()
        guard let source = shareableWindows[window.id],
              source.owningApplication?.processID == window.processIdentifier else {
            throw WindowPreviewError.windowUnavailable
        }
        if let existing = activeSession {
            await stop(sessionID: existing.id)
        }
        try Task.checkCancellation()

        let filter = SCContentFilter(desktopIndependentWindow: source)
        let configuration = SCStreamConfiguration()
        let scale = min(
            ScreenCapturePreviewController.backingScale(for: source.frame),
            1920 / source.frame.width,
            1920 / source.frame.height
        )
        configuration.width = max(1, min(1920, Int(source.frame.width * scale)))
        configuration.height = max(
            1,
            min(1920, Int(Double(configuration.width) * source.frame.height / source.frame.width))
        )
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.capturesAudio = false
        configuration.showsCursor = false

        let contentView = PreviewContentView()
        let bridge = StreamOutputBridge(controller: self, queue: sampleQueue)
        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: bridge
        )
        let panel = makePanel(for: window, contentView: contentView)

        let session = Session(
            id: sessionID,
            stream: stream,
            panel: panel,
            displayLayer: contentView.displayLayer,
            bridge: bridge
        )
        session.onReady = onReady
        session.onEnd = onEnd
        activeSession = session

        session.firstFrameTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.handleFirstFrameTimeout(sessionID: sessionID)
        }

        do {
            try stream.addStreamOutput(
                bridge,
                type: .screen,
                sampleHandlerQueue: sampleQueue
            )
            try await stream.startCapture()
        } catch {
            detach(session)
            try? await stream.stopCapture()
            throw error
        }

        guard activeSession === session else {
            try? await stream.stopCapture()
            throw CancellationError()
        }
    }

    func stop(sessionID: UUID) async {
        guard let session = activeSession, session.id == sessionID else { return }
        detach(session)
        try? await session.stream.stopCapture()
    }
}

extension ScreenCapturePreviewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let session = activeSession,
              notification.object as? NSPanel === session.panel else {
            return
        }
        finishSession(session, reason: nil)
    }
}

extension ScreenCapturePreviewController {
    fileprivate func deliverFrame(
        from stream: SCStream,
        sampleBuffer: CMSampleBuffer
    ) {
        guard let session = activeSession, session.stream === stream else { return }
        if session.displayLayer.status == .failed {
            session.displayLayer.flush()
        }
        guard session.displayLayer.isReadyForMoreMediaData else { return }
        ScreenCapturePreviewController.displayImmediately(sampleBuffer)
        session.displayLayer.enqueue(sampleBuffer)

        guard !session.didDeliverFirstFrame else { return }
        session.didDeliverFirstFrame = true
        session.firstFrameTask?.cancel()
        session.firstFrameTask = nil
        session.panel.orderFrontRegardless()
        session.onReady?()
    }

    fileprivate func sourceEnded(for stream: SCStream) {
        guard let session = activeSession, session.stream === stream else { return }
        finishSession(session, reason: "The previewed window is no longer available.")
    }

    fileprivate func sourceBlanked(for stream: SCStream) {
        guard let session = activeSession, session.stream === stream else { return }
        finishSession(
            session,
            reason: "The source window stopped sharing visible content. Restore it and start a new preview."
        )
    }

    fileprivate func streamDidStop(_ stream: SCStream, error: Error) {
        guard let session = activeSession, session.stream === stream else { return }
        finishSession(session, reason: error.localizedDescription)
    }

    private func handleFirstFrameTimeout(sessionID: UUID) {
        guard let session = activeSession,
              session.id == sessionID,
              !session.didDeliverFirstFrame else {
            return
        }
        finishSession(session, reason: WindowPreviewError.firstFrameTimeout.localizedDescription)
    }

    private func finishSession(_ session: Session, reason: String?) {
        guard activeSession === session, !session.didNotifyEnd else { return }
        session.didNotifyEnd = true
        let onEnd = session.onEnd
        detach(session)
        Task { [stream = session.stream] in
            try? await stream.stopCapture()
        }
        onEnd?(reason)
    }

    private func detach(_ session: Session) {
        guard activeSession === session else { return }
        activeSession = nil
        session.firstFrameTask?.cancel()
        session.firstFrameTask = nil
        session.onReady = nil
        session.onEnd = nil
        session.panel.delegate = nil
        session.panel.close()
        session.displayLayer.flushAndRemoveImage()
        try? session.stream.removeStreamOutput(session.bridge, type: .screen)
    }

    private func makePanel(
        for window: PreviewWindow,
        contentView: PreviewContentView
    ) -> NSPanel {
        let contentSize = fittedContentSize(for: window)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "\(window.applicationName) — Live Preview"
        panel.setAccessibilityLabel(
            "View-only live preview of \(window.summary.displayName)"
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 240, height: 160)
        panel.contentView = contentView
        panel.delegate = self
        if let visible = targetScreen()?.visibleFrame {
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            ))
        }
        return panel
    }

    private func fittedContentSize(for window: PreviewWindow) -> NSSize {
        let aspect = max(window.frame.width, 1) / max(window.frame.height, 1)
        var limit = NSSize(width: 560, height: 400)
        if let visible = targetScreen()?.visibleFrame {
            limit.width = min(limit.width, visible.width * 0.8)
            limit.height = min(limit.height, visible.height * 0.8)
        }
        var size = NSSize(width: limit.width, height: limit.width / aspect)
        if size.height > limit.height {
            size = NSSize(width: limit.height * aspect, height: limit.height)
        }
        return size
    }

    private func targetScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: {
            NSMouseInRect(mouseLocation, $0.frame, false)
        }) ?? .main ?? NSScreen.screens.first
    }

    private static func backingScale(for frame: CGRect) -> CGFloat {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        var bestScale: CGFloat = 0
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let quartzFrame = CGRect(
                x: screen.frame.minX,
                y: primaryMaxY - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
            let intersection = quartzFrame.intersection(frame)
            guard !intersection.isNull else { continue }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestScale = screen.backingScaleFactor
            }
        }
        return bestScale > 0 ? bestScale : 2
    }

    private static func displayImmediately(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ), CFArrayGetCount(attachments) > 0,
            let raw = CFArrayGetValueAtIndex(attachments, 0) else {
            return
        }
        let dictionary = unsafeBitCast(raw, to: NSMutableDictionary.self)
        dictionary[kCMSampleAttachmentKey_DisplayImmediately] = kCFBooleanTrue
    }
}

private final class Session {
    let id: UUID
    let stream: SCStream
    let panel: NSPanel
    let displayLayer: AVSampleBufferDisplayLayer
    let bridge: StreamOutputBridge
    var onReady: (() -> Void)?
    var onEnd: ((String?) -> Void)?
    var firstFrameTask: Task<Void, Never>?
    var didDeliverFirstFrame = false
    var didNotifyEnd = false

    init(
        id: UUID,
        stream: SCStream,
        panel: NSPanel,
        displayLayer: AVSampleBufferDisplayLayer,
        bridge: StreamOutputBridge
    ) {
        self.id = id
        self.stream = stream
        self.panel = panel
        self.displayLayer = displayLayer
        self.bridge = bridge
    }
}

private final class PreviewContentView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}

private final class StreamOutputBridge: NSObject, SCStreamOutput, SCStreamDelegate,
    @unchecked Sendable {
    private weak var controller: ScreenCapturePreviewController?
    private let queue: DispatchQueue
    private var deliveryPending = false
    private var didReportEnd = false

    init(controller: ScreenCapturePreviewController, queue: DispatchQueue) {
        self.controller = controller
        self.queue = queue
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let status = StreamOutputBridge.frameStatus(of: sampleBuffer) else {
            return
        }
        switch status {
        case .complete:
            break
        case .stopped:
            reportEndOnce { $0.sourceEnded(for: stream) }
            return
        case .blank, .suspended:
            reportEndOnce { $0.sourceBlanked(for: stream) }
            return
        default:
            return
        }
        guard CMSampleBufferDataIsReady(sampleBuffer),
              CMSampleBufferGetImageBuffer(sampleBuffer) != nil else {
            return
        }
        guard !deliveryPending else { return }
        deliveryPending = true

        Task { @MainActor [weak self, weak stream] in
            guard let self, let stream else { return }
            self.controller?.deliverFrame(from: stream, sampleBuffer: sampleBuffer)
            self.queue.async { [weak self] in
                self?.deliveryPending = false
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in
            self?.reportEndOnce { $0.streamDidStop(stream, error: error) }
        }
    }

    private func reportEndOnce(
        _ action: @escaping @MainActor (ScreenCapturePreviewController) -> Void
    ) {
        guard !didReportEnd else { return }
        didReportEnd = true
        let controller = self.controller
        Task { @MainActor in
            guard let controller else { return }
            action(controller)
        }
    }

    private static func frameStatus(of sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentsArray.first,
            let rawStatus = attachments[.status] as? Int else {
            return nil
        }
        return SCFrameStatus(rawValue: rawStatus)
    }
}
