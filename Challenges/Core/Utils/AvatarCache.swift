import UIKit

/// Stores and retrieves avatar images from the app's Documents directory.
/// This gives instant local access without waiting for CloudKit to round-trip.
enum AvatarCache {

    private static func url(for userID: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatar_\(userID).jpg")
    }

    /// Writes the image to disk and returns the local file URL.
    @discardableResult
    static func save(_ image: UIImage, userID: String) -> URL? {
        let sized = image.preparingThumbnail(of: CGSize(width: 400, height: 400)) ?? image
        guard let data = sized.jpegData(compressionQuality: 0.8) else { return nil }
        let destination = url(for: userID)
        try? data.write(to: destination)
        return destination
    }

    /// Returns the cached image if it exists on disk.
    static func load(userID: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: userID).path)
    }

    /// Returns the local file URL if the file exists on disk.
    static func localURL(for userID: String) -> URL? {
        let u = url(for: userID)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Writes raw JPEG data from a CKAsset to the cache. Call this after fetching a user record.
    static func cache(data: Data, userID: String) {
        let destination = url(for: userID)
        try? data.write(to: destination)
    }
}
