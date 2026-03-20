import Foundation
import Observation

@Observable
final class ProfileViewModel {

    var displayName: String = ""
    var hasAppleWatch: Bool = false
    var isSaving: Bool = false
    var error: String? = nil

    private let ck = CloudKitManager.shared

    @MainActor
    func load(user: AppUser) {
        displayName = user.displayName
        hasAppleWatch = user.hasAppleWatch
    }

    @MainActor
    func save(user: AppUser) async {
        isSaving = true
        defer { isSaving = false }
        var updated = user
        updated.displayName = displayName.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(updated.displayName, forKey: "displayName")
        do {
            try await ck.saveUser(updated)
            UserSession.shared.update(user: updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func signOut() {
        AuthManager.shared.signOut()
        UserSession.shared.clear()
    }
}
