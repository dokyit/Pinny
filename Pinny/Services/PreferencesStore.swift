import Foundation

final class PreferencesStore {
    private enum Key {
        static let onboardingCompleted = "onboardingCompleted"
        static let shortcutConfiguration = "shortcutConfiguration"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Key.onboardingCompleted) }
        set { defaults.set(newValue, forKey: Key.onboardingCompleted) }
    }

    var shortcutConfiguration: HotKeyConfiguration {
        get {
            guard
                let data = defaults.data(forKey: Key.shortcutConfiguration),
                let value = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data)
            else {
                return .controlZ
            }
            return value
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.shortcutConfiguration)
        }
    }
}
