import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ProfileViewModel {

    var displayName: String = ""
    var hasAppleWatch: Bool = false
    var isSaving: Bool = false
    var error: String? = nil
    var profilePhoto: UIImage? = nil

    private let ck = CloudKitManager.shared
    private var userID: String = ""
    private var originalDisplayName: String = ""

    @MainActor
    func load(user: AppUser) {
        userID = user.id
        displayName = user.displayName
        originalDisplayName = user.displayName
        hasAppleWatch = user.hasAppleWatch
        profilePhoto = AvatarCache.load(userID: user.id)
    }

    func saveProfilePhoto(_ image: UIImage) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AvatarCache.save(image, userID: userID)
        profilePhoto = image
        Task {
            guard var user = UserSession.shared.currentUser else { return }
            user.avatarURL = AvatarCache.localURL(for: userID)
            UserSession.shared.update(user: user)
            let jpegData = image.preparingThumbnail(of: CGSize(width: 400, height: 400))
                .flatMap { $0.jpegData(compressionQuality: 0.8) }
            do {
                try await ck.saveUser(user, avatarData: jpegData)
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
        }
    }

    @MainActor
    func save(user: AppUser) async {
        let trimmed = displayName.trimmingCharacters(in: .whitespaces)
        // Skip the CloudKit write if nothing actually changed.
        guard !trimmed.isEmpty, trimmed != originalDisplayName else { return }
        isSaving = true
        defer { isSaving = false }
        var updated = user
        updated.displayName = trimmed
        UserDefaults.standard.set(trimmed, forKey: "displayName")
        originalDisplayName = trimmed
        do {
            try await ck.saveUser(updated)
            UserSession.shared.update(user: updated)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func redetectWatch() async {
        let detected = await WatchDetector().detectAppleWatch()
        hasAppleWatch = detected
        UserDefaults.standard.set(detected, forKey: "hasAppleWatch")
        guard var user = UserSession.shared.currentUser else { return }
        user.hasAppleWatch = detected
        UserSession.shared.update(user: user)
        do {
            try await ck.saveUser(user)
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
