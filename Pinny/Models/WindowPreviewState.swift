import CoreGraphics
import Foundation

struct PreviewWindow: Equatable, Identifiable {
    let id: CGWindowID
    let processIdentifier: pid_t
    let applicationName: String
    let title: String?
    let frame: CGRect

    var summary: PinnedWindowSummary {
        PinnedWindowSummary(applicationName: applicationName, windowTitle: title)
    }
}

struct PreviewWindowSelection: Equatable {
    let processIdentifier: pid_t
    let title: String?
    let frame: CGRect?
}

enum WindowPreviewState: Equatable {
    case idle
    case loading
    case choosing([PreviewWindow])
    case starting(PreviewWindow)
    case active(PreviewWindow)
    case failed(String)

    var canStop: Bool {
        switch self {
        case .loading, .choosing, .starting, .active:
            return true
        case .idle, .failed:
            return false
        }
    }

    var activeWindow: PreviewWindow? {
        if case .active(let window) = self {
            return window
        }
        return nil
    }
}
