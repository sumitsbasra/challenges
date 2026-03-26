import SwiftUI

// MARK: - View Model

@MainActor
@Observable
final class JoinChallengeViewModel {

    var code: String = "" {
        didSet {
            let upper = code.uppercased().filter { $0.isLetter || $0.isNumber }
            if upper != code { code = upper }
            if code.count > 6 { code = String(code.prefix(6)) }
            if code.count == 6 { Task { await lookupChallenge() } }
            if code.count < 6 { previewChallenge = nil; error = nil; alreadyJoined = false }
        }
    }
    var userID: String? = nil
    var previewChallenge: Challenge? = nil
    var alreadyJoined = false
    var isLooking = false
    var isJoining = false
    var error: String? = nil
    var joined = false
    var participantCount: Int = 0

    private let ck = CloudKitManager.shared

    @MainActor
    func lookupChallenge() async {
        guard code.count == 6 else { return }
        isLooking = true
        error = nil
        alreadyJoined = false
        defer { isLooking = false }
        do {
            let challenge = try await ck.fetchChallenge(inviteCode: code)
            // Check membership immediately so the UI can reflect it at preview time
            let existing = try await ck.fetchParticipations(challengeID: challenge.id)
            participantCount = existing.filter { $0.status == .active }.count
            if let uid = userID, existing.contains(where: { $0.user.id == uid }) {
                alreadyJoined = true
            }
            previewChallenge = challenge
        } catch let e as CloudKitError {
            error = e.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func joinChallenge(userID: String, displayName: String, hasWatch: Bool) async {
        guard let challenge = previewChallenge else { return }
        isJoining = true
        error = nil
        defer { isJoining = false }

        do {
            // Check if user is already a participant before saving
            let existing = try await ck.fetchParticipations(challengeID: challenge.id)
            if existing.contains(where: { $0.user.id == userID }) {
                error = "You're already in this challenge."
                return
            }

            let participation = Participation(
                id: UUID().uuidString,
                challengeID: challenge.id,
                user: AppUser(id: userID, displayName: displayName, appleUserID: "", hasAppleWatch: hasWatch),
                joinedAt: Date(),
                status: .active,
                hasAppleWatch: hasWatch
            )
            try await ck.saveParticipation(participation)
            joined = true
        } catch {
            if self.error == nil { self.error = error.localizedDescription }
        }
    }
}
