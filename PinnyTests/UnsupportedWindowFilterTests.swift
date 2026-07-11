import Testing
@testable import Pinny

@Suite("Unsupported window filtering")
struct UnsupportedWindowFilterTests {
    @Test
    func testRejectsDockAndOtherProtectedSystemUI() {
        #expect(UnsupportedWindowFilter.rejectionReason(
            bundleIdentifier: "com.apple.dock",
            applicationName: "Dock",
            role: "AXWindow"
        ) != nil)
    }

    @Test
    func testRejectsNonWindowRole() {
        #expect(UnsupportedWindowFilter.rejectionReason(
            bundleIdentifier: "com.apple.TextEdit",
            applicationName: "TextEdit",
            role: "AXMenuBar"
        ) != nil)
    }

    @Test
    func testAllowsNormalFinderWindow() {
        #expect(UnsupportedWindowFilter.rejectionReason(
            bundleIdentifier: "com.apple.finder",
            applicationName: "Finder",
            role: "AXWindow"
        ) == nil)
    }

    @Test
    func testAllowsSheetAsIndividualWindowTarget() {
        #expect(UnsupportedWindowFilter.rejectionReason(
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            role: "AXSheet"
        ) == nil)
    }
}
