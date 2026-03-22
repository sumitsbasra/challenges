import Foundation
import Observation

@MainActor
@Observable
final class NewChallengeViewModel {

    var title: String = ""
    var startDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date())! {
        didSet {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            if startDate < tomorrow { startDate = tomorrow }
            if endDate < startDate { endDate = startDate }
        }
    }
    var endDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date())! {
        didSet {
            if endDate < startDate { endDate = startDate }
        }
    }
    var maxParticipants: Int = 50

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
            startDate: startDate,
            endDate: endDate,
            status: .pending,
            inviteCode: inviteCode,
            maxParticipants: maxParticipants,
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
            self.error = "Challenge created but auto-join failed: \(error.localizedDescription)"
            print("[NewChallenge] saveParticipation failed after 3 attempts: \(error)")
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
