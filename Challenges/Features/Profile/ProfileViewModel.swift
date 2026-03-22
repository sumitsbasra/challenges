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

    @MainActor
    func load(user: AppUser) {
        displayName = user.displayName
        hasAppleWatch = user.hasAppleWatch
        loadProfilePhoto()
    }

    func loadProfilePhoto() {
        if let data = UserDefaults.standard.data(forKey: "profilePhotoData"),
           let image = UIImage(data: data) {
            profilePhoto = image
        }
    }

    func saveProfilePhoto(data: Data) {
        guard let image = UIImage(data: data) else { return }
        // Resize longest dimension to 600pt, preserving aspect ratio
        let maxDimension: CGFloat = 600
        let scale = maxDimension / max(image.size.width, image.size.height)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        if let jpeg = resized.jpegData(compressionQuality: 0.85) {
            UserDefaults.standard.set(jpeg, forKey: "profilePhotoData")
            profilePhoto = resized
        }
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
    func redetectWatch() async {
        let detected = await WatchDetector().detectAppleWatch()
        hasAppleWatch = detected
        UserDefaults.standard.set(detected, forKey: "hasAppleWatch")
        guard var user = UserSession.shared.currentUser else { return }
        user.hasAppleWatch = detected
        UserSession.shared.update(user: user)
        try? await ck.saveUser(user)
    }

    @MainActor
    func signOut() {
        AuthManager.shared.signOut()
        UserSession.shared.clear()
    }
}
