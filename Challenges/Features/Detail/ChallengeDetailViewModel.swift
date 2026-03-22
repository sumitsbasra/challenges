import Foundation
import Observation

@MainActor
@Observable
final class ChallengeDetailViewModel {

    var challenge: Challenge
    var participations: [Participation] = []

    /// True while the initial participations + current-user scores are loading.
    var isLoading: Bool = false
    /// True while the full leaderboard scores are being fetched.
    var isLoadingLeaderboard: Bool = false
    /// Set after `loadLeaderboard()` completes so we don't re-fetch on every re-appear.
    var leaderboardLoaded: Bool = false

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
        let cal = Calendar.current
        switch challenge.status {
        case .pending:
            let today = cal.startOfDay(for: Date())
            let start = cal.startOfDay(for: challenge.startDate)
            let days = cal.dateComponents([.day], from: today, to: start).day ?? 0
            return "Starts in \(days) day\(days == 1 ? "" : "s")"
        case .active:
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left"
        case .completed:
            return "Challenge complete"
        }
    }

    // MARK: - Phase 1: Initial Load

    /// Shows cached participations instantly, then refreshes from CloudKit in the background.
    @MainActor
    func load() async {
        // Show cached data immediately — no spinner if we have something.
        if let cached = ParticipationCache.load(challengeID: challenge.id) {
            participations = cached
            isLoading = false
        } else {
            isLoading = true
        }

        await fetchAndUpdate()

        await CloudKitManager.shared.registerSubscriptions(forActiveChallengeIDs: [challenge.id])

        // If we created this challenge but still aren't a participant (propagation delay), retry.
        let userID = UserSession.shared.userID ?? ""
        if challenge.creatorID == userID,
           !participations.contains(where: { $0.user.id == userID }) {
            Task {
                try? await Task.sleep(for: .seconds(3))
                await silentParticipationRefresh()
            }
        }
    }

    @MainActor
    private func fetchAndUpdate() async {
        isLoading = participations.isEmpty  // spinner only when we have nothing to show
        error = nil
        defer { isLoading = false }

        do {
            var parts = try await ck.fetchParticipations(challengeID: challenge.id)

            let userID = UserSession.shared.userID ?? ""
            if let myPart = parts.first(where: { $0.user.id == userID }) {
                let myScores = try await ck.fetchDailyScores(participationID: myPart.id)
                if let idx = parts.firstIndex(where: { $0.id == myPart.id }) {
                    parts[idx].dailyScores = myScores.sorted { $0.date < $1.date }
                }
            }

            participations = parts
            lastFetchDate = Date()
            ParticipationCache.save(parts, challengeID: challenge.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func silentParticipationRefresh() async {
        guard let parts = try? await ck.fetchParticipations(challengeID: challenge.id),
              !parts.isEmpty else { return }
        let userID = UserSession.shared.userID ?? ""
        // Only update if we now have a real record for ourselves
        if parts.contains(where: { $0.user.id == userID }) {
            participations = parts
        }
    }

    // MARK: - Phase 2: Leaderboard Load

    /// Fetches all participants' daily scores. Called when the leaderboard section
    /// scrolls into view. No-ops if already loaded.
    @MainActor
    func loadLeaderboard() async {
        guard !leaderboardLoaded, !isLoadingLeaderboard else { return }
        isLoadingLeaderboard = true
        defer { isLoadingLeaderboard = false }

        do {
            let allScores = try await ck.fetchDailyScores(challengeID: challenge.id)
            for i in participations.indices {
                participations[i].dailyScores = allScores
                    .filter { $0.participationID == participations[i].id }
                    .sorted { $0.date < $1.date }
            }
            leaderboardLoaded = true
            lastFetchDate = Date()
        } catch {
            // Non-fatal — partial data is better than nothing; user can pull-to-refresh.
            print("[DetailVM] Leaderboard load failed: \(error)")
        }
    }

    // MARK: - Refresh (pull-to-refresh reloads everything)

    @MainActor
    func refresh() async {
        leaderboardLoaded = false
        await fetchAndUpdate()
        await loadLeaderboard()
    }

    // MARK: - Delete / Leave

    @MainActor
    func deleteChallenge() async throws {
        try await ck.deleteChallenge(id: challenge.id)
        NotificationCenter.default.post(name: .participationDidChange, object: nil)
    }

    @MainActor
    func leaveChallenge(userID: String) async throws {
        guard let part = participations.first(where: { $0.user.id == userID }) else { return }
        try await ck.leaveChallenge(participationID: part.id)
        NotificationCenter.default.post(name: .participationDidChange, object: nil)
    }

    // MARK: - Incremental Score Update (CloudKit push)

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
            print("[DetailVM] Score update failed: \(error)")
        }
    }
}
