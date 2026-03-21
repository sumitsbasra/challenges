import Foundation
import Observation

/// Observable current user state. Observed by views throughout the app.
@Observable
final class UserSession {

    static let shared = UserSession()

    var currentUser: AppUser? = nil
    var isOnboarded: Bool = false

    private init() {
        loadCachedUser()
    }

    var userID: String? { currentUser?.id }
    var isAuthenticated: Bool { currentUser != nil }

    func update(user: AppUser) {
        currentUser = user
        isOnboarded = true
        cachUser(user)
    }

    func clear() {
        currentUser = nil
        isOnboarded = false
        UserDefaults.standard.removeObject(forKey: "cachedUser")
    }

    // MARK: - Local persistence

    private func cachUser(_ user: AppUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "cachedUser")
        }
    }

    private func loadCachedUser() {
        guard let data = UserDefaults.standard.data(forKey: "cachedUser"),
              let user = try? JSONDecoder().decode(AppUser.self, from: data) else { return }
        currentUser = user
        isOnboarded = true
    }
}
