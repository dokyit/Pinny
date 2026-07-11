import Testing
@testable import Pinny

@Suite("Window identity")
struct WindowIdentityTests {
    @Test
    func testSameProcessAndElementHashAreEqual() {
        #expect(
            WindowIdentity(processIdentifier: 10, accessibilityElementHash: 99)
                == WindowIdentity(processIdentifier: 10, accessibilityElementHash: 99)
        )
    }

    @Test
    func testTwoWindowsInSameApplicationAreDistinct() {
        #expect(
            WindowIdentity(processIdentifier: 10, accessibilityElementHash: 99)
                != WindowIdentity(processIdentifier: 10, accessibilityElementHash: 100)
        )
    }

    @Test
    func testSameElementHashInDifferentApplicationsIsDistinct() {
        #expect(
            WindowIdentity(processIdentifier: 10, accessibilityElementHash: 99)
                != WindowIdentity(processIdentifier: 11, accessibilityElementHash: 99)
        )
    }
}
