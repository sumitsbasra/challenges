import Foundation

struct AppUser: Identifiable, Hashable, Codable {
    let id: String          // = CKRecord.creatorUserRecordID.recordName
    var displayName: String
    var appleUserID: String
    var hasAppleWatch: Bool
    var avatarURL: URL?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AppUser, rhs: AppUser) -> Bool {
        lhs.id == rhs.id
    }
}
