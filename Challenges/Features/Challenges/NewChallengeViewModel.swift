import Foundation
import Observation

@Observable
final class NewChallengeViewModel {

    var title: String = ""
    var startDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    var maxParticipants: Int = 10

    var isSaving: Bool = false
    var error: String? = nil
    var createdChallenge: Challenge? = nil

    var endDate: Date { Challenge.makeEndDate(from: startDate) }
    var inviteCode: String = Self.generateCode()
    var canCreate: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private let ck = CloudKitManager.shared

    @MainActor
    func create(creatorID: String) async {
        guard canCreate else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }

        let challenge = Challenge(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespaces),
            creatorID: creatorID,
            startDate: startDate,
            endDate: endDate,
            status: .pending,
            inviteCode: inviteCode,
            maxParticipants: maxParticipants,
            createdAt: Date()
        )

        do {
            try await ck.saveChallenge(challenge)
            createdChallenge = challenge
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func generateCode() -> String {
        // Unambiguous charset: no O/0, I/1
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }
}
