import Foundation
import CloudKit

enum CloudKitError: LocalizedError {
    case notAuthenticated
    case recordNotFound(String)
    case saveFailed(CKError)
    case fetchFailed(CKError)
    case inviteCodeNotFound
    case challengeAlreadyCompleted
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
        case .challengeAlreadyCompleted:
            return "This challenge has already ended and can't be joined."
        case .challengeFull:
            return "This challenge is full."
        case .alreadyParticipating:
            return "You're already in this challenge."
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    /// User-facing text for any error thrown by a CloudKit call.
    ///
    /// Raw `CKError.localizedDescription` is Apple's internal phrasing — a signed-out
    /// user sees "This request requires an authenticated account," which means nothing
    /// to someone who just tapped an invite link. Call this anywhere an error reaches
    /// the UI so the cause is actionable.
    static func message(for error: Error) -> String {
        if let known = error as? CloudKitError {
            return known.errorDescription ?? "Something went wrong."
        }
        guard let ck = error as? CKError else { return "Something went wrong. Try again." }
        switch ck.code {
        case .notAuthenticated:
            return "Sign in to iCloud in Settings to use Challenges."
        case .networkUnavailable, .networkFailure:
            return "No internet connection."
        case .quotaExceeded:
            return "Your iCloud storage is full."
        case .requestRateLimited, .zoneBusy, .serviceUnavailable, .serverResponseLost:
            return "iCloud is busy. Try again in a moment."
        case .permissionFailure:
            return "Challenges doesn't have permission to use iCloud."
        default:
            return "Something went wrong. Try again."
        }
    }
}
