import Foundation

@MainActor
protocol WindowPreviewCapturing: AnyObject {
    func availableWindows() async throws -> [PreviewWindow]
    func start(
        window: PreviewWindow,
        sessionID: UUID,
        onReady: @escaping () -> Void,
        onEnd: @escaping (String?) -> Void
    ) async throws
    func stop(sessionID: UUID) async
}

@MainActor
final class WindowPreviewManager {
    private let capture: WindowPreviewCapturing
    private var sessionID: UUID?
    private var task: Task<Void, Never>?

    private(set) var state: WindowPreviewState = .idle {
        didSet { onStateChange?(state) }
    }

    var onStateChange: ((WindowPreviewState) -> Void)?

    init(capture: WindowPreviewCapturing) {
        self.capture = capture
    }

    func begin(selection: PreviewWindowSelection?) {
        invalidateSession()

        let newSessionID = UUID()
        sessionID = newSessionID
        state = .loading

        task = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, sessionID == newSessionID else { return }
            do {
                let windows = try await capture.availableWindows()
                guard !Task.isCancelled, sessionID == newSessionID else { return }
                handleEnumeratedWindows(
                    windows,
                    selection: selection,
                    sessionID: newSessionID
                )
            } catch {
                guard !Task.isCancelled, sessionID == newSessionID else { return }
                invalidateSession()
                state = .failed(error.localizedDescription)
            }
        }
    }

    func select(_ window: PreviewWindow) {
        guard case .choosing(let choices) = state,
              choices.contains(window),
              let currentSessionID = sessionID else {
            return
        }
        start(window: window, sessionID: currentSessionID)
    }

    func stop() {
        invalidateSession()
        state = .idle
    }

    static func matchingWindow(
        in windows: [PreviewWindow],
        selection: PreviewWindowSelection
    ) -> PreviewWindow? {
        let sameProcess = windows.filter {
            $0.processIdentifier == selection.processIdentifier
        }
        guard !sameProcess.isEmpty else { return nil }

        if let frame = selection.frame {
            let boundsMatches = sameProcess.filter { candidate in
                abs(candidate.frame.origin.x - frame.origin.x) <= 2
                    && abs(candidate.frame.origin.y - frame.origin.y) <= 2
                    && abs(candidate.frame.width - frame.width) <= 2
                    && abs(candidate.frame.height - frame.height) <= 2
            }
            if boundsMatches.count == 1, let candidate = boundsMatches.first {
                let requestedTitle = selection.title?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if (requestedTitle ?? "").isEmpty
                    || candidate.title == selection.title {
                    return candidate
                }
            }
        }

        guard let title = selection.title,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let titleMatches = sameProcess.filter { candidate in
            guard let candidateTitle = candidate.title,
                  !candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return candidateTitle == title
        }
        return titleMatches.count == 1 ? titleMatches.first : nil
    }

    private func handleEnumeratedWindows(
        _ windows: [PreviewWindow],
        selection: PreviewWindowSelection?,
        sessionID expectedID: UUID
    ) {
        guard !windows.isEmpty else {
            invalidateSession()
            state = .failed("No shareable windows are available.")
            return
        }

        if let selection,
           let window = Self.matchingWindow(in: windows, selection: selection) {
            start(window: window, sessionID: expectedID)
            return
        }

        state = .choosing(sortedForDisplay(windows))
    }

    private func start(window: PreviewWindow, sessionID expectedID: UUID) {
        state = .starting(window)

        let onReady = { [weak self] in
            guard let self,
                  sessionID == expectedID,
                  case .starting(let current) = state,
                  current == window else {
                return
            }
            state = .active(window)
        }

        let onEnd = { [weak self] (reason: String?) in
            guard let self, sessionID == expectedID else { return }
            sessionID = nil
            task?.cancel()
            task = nil
            if let reason, !reason.isEmpty {
                state = .failed(reason)
            } else {
                state = .idle
            }
            Task { [capture] in
                await capture.stop(sessionID: expectedID)
            }
        }

        task = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, sessionID == expectedID else { return }
            do {
                try await capture.start(
                    window: window,
                    sessionID: expectedID,
                    onReady: onReady,
                    onEnd: onEnd
                )
            } catch {
                guard sessionID == expectedID else { return }
                invalidateSession()
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func invalidateSession() {
        let previousSessionID = sessionID
        sessionID = nil
        task?.cancel()
        task = nil
        guard let previousSessionID else { return }
        Task { [capture] in
            await capture.stop(sessionID: previousSessionID)
        }
    }

    private func sortedForDisplay(_ windows: [PreviewWindow]) -> [PreviewWindow] {
        windows.sorted { lhs, rhs in
            if lhs.applicationName != rhs.applicationName {
                return lhs.applicationName.localizedCaseInsensitiveCompare(
                    rhs.applicationName
                ) == .orderedAscending
            }
            let lhsTitle = lhs.title ?? ""
            let rhsTitle = rhs.title ?? ""
            if lhsTitle != rhsTitle {
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }
}
