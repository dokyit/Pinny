import Foundation
import Testing
@testable import Pinny

@Suite("Preference persistence")
struct PreferencesStoreTests {
    @Test
    func testOnboardingCompletionPersists() {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = PreferencesStore(defaults: defaults)
        first.onboardingCompleted = true

        let second = PreferencesStore(defaults: defaults)

        #expect(second.onboardingCompleted)
    }

    @Test
    func testShortcutConfigurationPersists() {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = HotKeyConfiguration(keyCode: 12, carbonModifiers: 4096, displayName: "⌃Q")
        let first = PreferencesStore(defaults: defaults)
        first.shortcutConfiguration = custom

        #expect(PreferencesStore(defaults: defaults).shortcutConfiguration == custom)
    }

    @Test
    func testMissingOrCorruptShortcutFallsBackToControlZ() {
        let (suiteName, defaults) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(PreferencesStore(defaults: defaults).shortcutConfiguration == .controlZ)

        defaults.set(Data([0xFF, 0x00]), forKey: "shortcutConfiguration")

        #expect(PreferencesStore(defaults: defaults).shortcutConfiguration == .controlZ)
    }

    private func makeIsolatedDefaults() -> (String, UserDefaults) {
        let suiteName = "PinnyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }
}
