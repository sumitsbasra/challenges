import Foundation
import Observation

@Observable
final class ChallengeDetailViewModel {

    var challenge: Challenge
    var participations: [Participation] = []
    var isLoading: Bool = false
    var lastFetchDate: Date = .distantPast
    var error: String? = nil

    private let ck = CloudKitManager.shared

    init(challenge: Challenge) {
        self.challenge = challenge
    }

    var rankedParticipations: [Participation] {
        ScoreAggregator.ranked(participations)
    }

    var currentUserParticipation: Participation? {
        let userID = UserSession.shared.userID ?? ""
        return participations.first { $0.user.id == userID }
    }

    var daysRemaining: Int {
        let now = Date()
        guard challenge.status == .active else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: now, to: challenge.endDate).day ?? 0)
    }

    var countdownText: String {
        switch challenge.status {
        case .pending:
            let days = Calendar.current.dateComponents([.day], from: Date(), to: challenge.startDate).day ?? 0
            return "Starts in \(days) day\(days == 1 ? "" : "s")"
        case .active:
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left"
        case .completed:
            return "Challenge complete"
        }
    }

    // MARK: - Load

    @MainActor
    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        await fetchAll()
        await CloudKitManager.shared.registerSubscriptions(forActiveChallengeIDs: [challenge.id])
    }

    @MainActor
    func refresh() async {
        await fetchAll()
    }

    // Full fetch of participations + scores.
    @MainActor
    private func fetchAll() async {
        do {
            var parts = try await ck.fetchParticipations(challengeID: challenge.id)
            let scores = try await ck.fetchDailyScores(challengeID: challenge.id)

            // Map scores to participations.
            for i in parts.indices {
                parts[i].dailyScores = scores.filter { $0.participationID == parts[i].id }
                    .sorted { $0.date < $1.date }
            }
            participations = parts
            lastFetchDate = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Called when a CloudKit subscription push arrives — merges only changed records.
    @MainActor
    func handleScoreUpdate() async {
        do {
            let updatedScores = try await ck.fetchDailyScores(challengeID: challenge.id,
                                                               since: lastFetchDate)
            for score in updatedScores {
                if let idx = participations.firstIndex(where: { $0.id == score.participationID }) {
                    if let scoreIdx = participations[idx].dailyScores.firstIndex(where: { $0.id == score.id }) {
                        participations[idx].dailyScores[scoreIdx] = score
                    } else {
                        participations[idx].dailyScores.append(score)
                        participations[idx].dailyScores.sort { $0.date < $1.date }
                    }
                }
            }
            lastFetchDate = Date()
        } catch {
            // Non-fatal: the next full refresh will catch it.
            print("[DetailVM] Score update failed: \(error)")
        }
    }
}
