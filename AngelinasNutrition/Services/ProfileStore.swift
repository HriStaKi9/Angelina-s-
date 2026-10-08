import Foundation
import Observation

/// Holds the user's profile and persists it to UserDefaults on every change.
@Observable
final class ProfileStore {
    private static let key = "userProfile.v1"
    private let defaults: UserDefaults

    var profile: UserProfile {
        didSet { save() }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = stored
        } else {
            profile = UserProfile()
        }
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }

    func reset() {
        profile = UserProfile()
        hasCompletedOnboarding = false
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
