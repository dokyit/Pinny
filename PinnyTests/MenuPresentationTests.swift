import CoreGraphics
import Testing
@testable import Pinny

@Suite("Menu status presentation")
struct MenuPresentationTests {
    @Test
    func testReadyPresentation() {
        let presentation = MenuPresentation.make(status: .ready, isAccessibilityTrusted: true)

        #expect(presentation.statusTitle == "Ready")
        #expect(presentation.actionTitle == "Pin Current Window")
        #expect(presentation.canToggleWindow)
    }

    @Test
    func testPinnedPresentationContainsApplicationAndWindowTitle() {
        let presentation = MenuPresentation.make(
            status: .windowPinned(PinnedWindowSummary(
                applicationName: "Safari",
                windowTitle: "YouTube"
            )),
            isAccessibilityTrusted: true
        )

        #expect(presentation.statusTitle == "Window pinned")
        #expect(presentation.statusDetail == "Pinned: Safari — YouTube")
        #expect(presentation.actionTitle == "Unpin Current Window")
    }

    @Test
    func testMissingPermissionTakesPresentationPriority() {
        let presentation = MenuPresentation.make(
            status: .shortcutRegistrationFailed("busy"),
            isAccessibilityTrusted: false
        )

        #expect(presentation.statusTitle == "Accessibility permission required")
        #expect(!presentation.canToggleWindow)
    }

    @Test
    func testUnablePresentationIncludesHonestReason() {
        let presentation = MenuPresentation.make(
            status: .unableToPin("Public API unavailable"),
            isAccessibilityTrusted: true
        )

        #expect(presentation.statusTitle == "Unable to pin this window")
        #expect(presentation.statusDetail == "Public API unavailable")
    }

    @Test
    func testShortcutRegistrationFailureTakesPriorityOverTransientStatus() {
        let presentation = MenuPresentation.make(
            status: .unableToPin("No focused window"),
            isAccessibilityTrusted: true,
            shortcutRegistrationFailure: "⌃Z is already registered by another application."
        )

        #expect(presentation.statusTitle == "Shortcut registration failed")
        #expect(presentation.statusDetail?.contains("already registered") == true)

        let pinnedPresentation = MenuPresentation.make(
            status: .windowPinned(PinnedWindowSummary(
                applicationName: "Safari",
                windowTitle: "Document"
            )),
            isAccessibilityTrusted: true,
            shortcutRegistrationFailure: "shortcut busy"
        )
        #expect(pinnedPresentation.actionTitle == "Unpin Current Window")
    }

    @Test
    func testRaiseFallbackNeverClaimsWindowIsPinned() {
        let presentation = MenuPresentation.make(
            status: .windowRaisedOnce(PinnedWindowSummary(
                applicationName: "Calculator",
                windowTitle: nil
            )),
            isAccessibilityTrusted: true
        )

        #expect(presentation.statusTitle == "Raised once (fallback)")
        #expect(presentation.statusDetail?.contains("It is not pinned") == true)
        #expect(presentation.actionTitle == "Pin Current Window")

        let failure = MenuPresentation.make(
            status: .unableToRaise("AXRaise is unsupported"),
            isAccessibilityTrusted: true
        )
        #expect(failure.statusTitle == "Unable to raise this window")
    }

    @Test
    func testHideAndRestorePresentationsIdentifyTheWindow() {
        let summary = PinnedWindowSummary(
            applicationName: "Notes",
            windowTitle: "Ideas"
        )

        let hidden = MenuPresentation.make(
            status: .windowHidden(summary),
            isAccessibilityTrusted: true
        )
        let shown = MenuPresentation.make(
            status: .windowShown(summary),
            isAccessibilityTrusted: true
        )

        #expect(hidden.statusTitle == "Window hidden")
        #expect(hidden.statusDetail == "Hidden: Notes — Ideas")
        #expect(shown.statusTitle == "Window restored")
        #expect(shown.statusDetail == "Restored: Notes — Ideas")
    }

    @Test
    func testIdlePreviewIsSelectableWithoutAccessibility() {
        let presentation = MenuPresentation.make(
            status: .accessibilityPermissionRequired,
            isAccessibilityTrusted: false,
            previewState: .idle
        )

        #expect(presentation.canToggleWindow)
        #expect(presentation.actionTitle == "Float Window Preview")
        #expect(presentation.statusTitle == "Ready")
        #expect(presentation.statusDetail == nil)
    }

    @Test
    func testActivePreviewCanCloseWithoutAccessibility() {
        let window = PreviewWindow(
            id: 7,
            processIdentifier: 42,
            applicationName: "Safari",
            title: "Docs",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        let presentation = MenuPresentation.make(
            status: .accessibilityPermissionRequired,
            isAccessibilityTrusted: false,
            previewState: .active(window)
        )

        #expect(presentation.canToggleWindow)
        #expect(presentation.actionTitle == "Close Preview")
        #expect(presentation.statusTitle == "Live preview")
        #expect(presentation.statusDetail == "Safari — Docs — View only")
    }

    @Test
    func testActivePreviewPreservesHideFailureReason() {
        let window = PreviewWindow(
            id: 8,
            processIdentifier: 42,
            applicationName: "Safari",
            title: "Docs",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        let presentation = MenuPresentation.make(
            status: .unableToHide("Cannot minimize"),
            isAccessibilityTrusted: true,
            previewState: .active(window)
        )

        #expect(presentation.actionTitle == "Close Preview")
        #expect(presentation.canToggleWindow)
        #expect(presentation.statusDetail?.contains("Cannot minimize") == true)
        #expect(presentation.statusDetail?.contains("Safari — Docs") == true)
    }

    @Test
    func testDuplicateShortcutReasonIsNotRepeated() {
        let presentation = MenuPresentation.make(
            status: .shortcutRegistrationFailed("busy"),
            isAccessibilityTrusted: true,
            shortcutRegistrationFailure: "busy",
            previewState: .idle
        )

        #expect(presentation.statusTitle == "Shortcut registration failed")
        #expect(presentation.statusDetail == "busy")
    }

    @Test
    func testPreviewFailureIsTruthful() {
        let presentation = MenuPresentation.make(
            status: .ready,
            isAccessibilityTrusted: true,
            previewState: .failed("Screen Recording permission is required.")
        )

        #expect(presentation.statusTitle == "Unable to show preview")
        #expect(presentation.statusDetail == "Screen Recording permission is required.")
        #expect(presentation.actionTitle == "Float Window Preview")
        #expect(presentation.canToggleWindow)
    }

    @Test
    func testShortcutFailureDoesNotHidePreviewError() {
        let presentation = MenuPresentation.make(
            status: .ready,
            isAccessibilityTrusted: true,
            shortcutRegistrationFailure: "⌃Z is already registered by another application.",
            previewState: .failed("capture interrupted")
        )

        #expect(presentation.statusTitle == "Unable to show preview")
        #expect(presentation.statusDetail?.contains("capture interrupted") == true)
        #expect(presentation.statusDetail?.contains("already registered") == true)
    }

    @Test
    func testChoosingLoadingAndStartingPresentations() {
        let window = PreviewWindow(
            id: 9,
            processIdentifier: 43,
            applicationName: "Notes",
            title: nil,
            frame: .zero
        )

        let loading = MenuPresentation.make(
            status: .ready,
            isAccessibilityTrusted: true,
            previewState: .loading
        )
        #expect(loading.statusTitle == "Finding windows…")
        #expect(loading.actionTitle == "Cancel Preview")

        let choosing = MenuPresentation.make(
            status: .ready,
            isAccessibilityTrusted: false,
            previewState: .choosing([window])
        )
        #expect(choosing.statusTitle == "Choose a window")
        #expect(choosing.actionTitle == "Cancel Preview")
        #expect(choosing.canToggleWindow)

        let starting = MenuPresentation.make(
            status: .ready,
            isAccessibilityTrusted: true,
            previewState: .starting(window)
        )
        #expect(starting.statusTitle == "Starting preview…")
        #expect(starting.actionTitle == "Cancel Preview")
    }
}
