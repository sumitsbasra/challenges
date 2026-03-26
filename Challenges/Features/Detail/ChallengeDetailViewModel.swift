import Foundation
import Observation
import CloudKit

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
        // Use rankedParticipations so totalPoints is already aggregated from dailyScores.
        // The raw participations array keeps totalPoints = 0 until ScoreAggregator runs.
        return rankedParticipations.first { $0.user.id == userID }
    }

    var daysRemaining: Int {
        let now = Date()
        guard challenge.status == .active else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: now, to: challenge.endDate).day ?? 0)
    }

    var countdownText: String {
        let cal  = Calendar.current
        let now  = Date()
        switch challenge.status {
        case .pending:
            let days = cal.dateComponents([.day],
                from: cal.startOfDay(for: now),
                to:   cal.startOfDay(for: challenge.startDate)).day ?? 0
            return days == 0 ? "Starts today" : "Starts in \(days) day\(days == 1 ? "" : "s")"
        case .active:
            if cal.isDateInToday(challenge.startDate) { return "Starts today" }
            if cal.isDateInToday(challenge.endDate)   { return "Ends today" }
            let daysToEnd = cal.dateComponents([.day],
                from: cal.startOfDay(for: now),
                to:   cal.startOfDay(for: challenge.endDate)).day ?? 0
            if daysToEnd == 1 { return "Ends tomorrow" }
            return "Ongoing"
        case .completed:
            return "Completed"
        }
    }

    // MARK: - Local status transition

    /// Applies `pending → active` or `active → completed` based on the current date.
    /// Updates the in-memory `challenge.status` immediately so the UI is correct, then
    /// fires a background CloudKit write so other clients receive the change.
    @MainActor
    private func applyLocalTransition() {
        let now = Date()
        if challenge.status == .pending && challenge.startDate <= now {
            challenge.status = .active
            let id = challenge.id
            Task { try? await CloudKitManager.shared.updateChallengeStatus(id, status: .active) }
            // Post so HomeView moves this challenge from upcomingChallenges to activeItems.
            NotificationCenter.default.post(name: .participationDidChange, object: nil)
        } else if challenge.status == .active && challenge.endDate < now {
            challenge.status = .completed
            let id = challenge.id
            Task { try? await CloudKitManager.shared.updateChallengeStatus(id, status: .completed) }
            NotificationCenter.default.post(name: .participationDidChange, object: nil)
        }
    }

    // MARK: - Phase 1: Initial Load

    /// Shows cached participations instantly, then refreshes from CloudKit in the background.
    @MainActor
    func load() async {
        // Apply any pending status transition before showing the UI so the
        // countdownText, leaderboard section title, and sync path are all correct.
        applyLocalTransition()

        // Show cached data immediately — no spinner if we have something.
        if let cached = ParticipationCache.load(challengeID: challenge.id) {
            participations = cached
            isLoading = false
        } else {
            isLoading = true
        }

        // Sync this challenge's scores first so CloudKit has the latest data
        // before we fetch — avoids showing stale/zero scores on first open.
        if challenge.status == .active {
            await SyncCoordinator.shared.syncChallenge(challenge)
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
            let ck = error as? CKError
            if ck?.code == .networkUnavailable || ck?.code == .networkFailure {
                if participations.isEmpty { self.error = "No internet connection." }
            } else {
                self.error = "Couldn't load. Pull down to try again."
            }
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
            self.error = "Couldn't load leaderboard. Pull down to try again."
        }
    }

    // MARK: - Refresh (pull-to-refresh reloads everything)

    @MainActor
    func refresh() async {
        leaderboardLoaded = false
        await fetchAndUpdate()
        await loadLeaderboard()
    }

    // MARK: - Edit (title + dates in one round-trip)

    @MainActor
    func update(title: String, startDate: Date, endDate: Date) async throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        let titleChanged = trimmedTitle != challenge.title
        let startChanged = startDate    != challenge.startDate
        let endChanged   = endDate      != challenge.endDate
        guard titleChanged || startChanged || endChanged else { return }

        try await ck.updateChallenge(
            id:        challenge.id,
            title:     titleChanged ? trimmedTitle : nil,
            startDate: startChanged ? startDate    : nil,
            endDate:   endChanged   ? endDate      : nil
        )

        // Update local model
        challenge.title     = trimmedTitle
        challenge.startDate = startDate
        challenge.endDate   = endDate

        // Notify list views so their cards update without a CloudKit re-fetch
        if titleChanged {
            NotificationCenter.default.post(
                name: .challengeDidRename,
                object: nil,
                userInfo: ["id": challenge.id, "title": trimmedTitle]
            )
        }
        if startChanged || endChanged {
            NotificationCenter.default.post(
                name: .challengeDatesDidChange,
                object: nil,
                userInfo: ["id": challenge.id, "startDate": startDate, "endDate": endDate]
            )
            Task { await NotificationScheduler.remove(challengeID: challenge.id) }
        }
    }

    // MARK: - Delete / Leave

    @MainActor
    func deleteChallenge() async throws {
        try await ck.deleteChallenge(id: challenge.id)
        await NotificationScheduler.remove(challengeID: challenge.id)
        NotificationCenter.default.post(name: .participationDidChange, object: nil)
    }

    @MainActor
    func leaveChallenge(userID: String) async throws {
        guard let part = participations.first(where: { $0.user.id == userID }) else { return }
        try await ck.leaveChallenge(participationID: part.id)
        await NotificationScheduler.remove(challengeID: challenge.id)
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
            self.error = "Couldn't refresh scores. Pull down to try again."
        }
    }
}
