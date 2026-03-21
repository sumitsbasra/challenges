import Foundation
import CloudKit

enum CloudKitError: LocalizedError {
    case notAuthenticated
    case recordNotFound(String)
    case saveFailed(CKError)
    case fetchFailed(CKError)
    case inviteCodeNotFound
    case challengeFull
    case alreadyParticipating
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to iCloud to use Challenges."
        case .recordNotFound(let id):
            return "Record not found: \(id)"
        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch: \(error.localizedDescription)"
        case .inviteCodeNotFound:
            return "No challenge found with that invite code. Check the code and try again."
        case .challengeFull:
            return "This challenge is full."
        case .alreadyParticipating:
            return "You're already in this challenge."
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
