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
}
