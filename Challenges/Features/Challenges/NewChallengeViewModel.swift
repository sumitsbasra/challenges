import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class NewChallengeViewModel {

    static let defaultDurationDays = 7

    var title: String = ""

    var startDate: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    )
    var endDate: Date = NewChallengeViewModel.endOfDay(
        Calendar.current.date(byAdding: .day, value: NewChallengeViewModel.defaultDurationDays, to: Date()) ?? Date()
    )

    /// Returns 23:59:59 on the same calendar day as `date`.
    static func endOfDay(_ date: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 23; comps.minute = 59; comps.second = 59
        return Calendar.current.date(from: comps) ?? date
    }
    var durationDays: Int {
        max(1, (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)
    }

    var isSaving: Bool = false
    var error: String? = nil
    var createdChallenge: Challenge? = nil

    var inviteCode: String = NewChallengeViewModel.generateCode()
    var canCreate: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private let ck = CloudKitManager.shared

    @MainActor
    func create(creator: AppUser) async {
        guard canCreate else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }

        let challenge = Challenge(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespaces),
            creatorID: creator.id,
            startDate: Calendar.current.startOfDay(for: startDate),
            endDate: NewChallengeViewModel.endOfDay(endDate),
            status: .pending,
            inviteCode: inviteCode,
            createdAt: Date()
        )

        // Step 1: save the challenge
        do {
            try await ck.saveChallenge(challenge)
        } catch {
            self.error = "Could not create challenge: \(error.localizedDescription)"
            return
        }

        // Step 2: auto-join creator (separate save — challenge is already committed above)
        let participation = Participation(
            id: UUID().uuidString,
            challengeID: challenge.id,
            user: creator,
            joinedAt: Date(),
            status: .active,
            hasAppleWatch: creator.hasAppleWatch
        )
        var lastParticipationError: Error? = nil
        for attempt in 0..<3 {
            do {
                try await ck.saveParticipation(participation)
                lastParticipationError = nil
                break
            } catch {
                lastParticipationError = error
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
        if let error = lastParticipationError {
            self.error = "Challenge created but auto-join failed. Please try again."
            Logger.cloudKit.error("NewChallenge saveParticipation failed after 3 attempts: \(error.localizedDescription, privacy: .public)")
            return  // Don't show the success screen — creator has no participation record
        }

        createdChallenge = challenge
        NotificationCenter.default.post(name: .participationDidChange, object: nil)
    }

    static func generateCode() -> String {
        // Unambiguous charset: no O/0, I/1
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
