import Foundation
import Observation
import CloudKit
import HealthKit

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

    /// The current user's standing: rank, field size, and point gaps. Nil if the user
    /// isn't a participant or there are no participants yet.
    struct Standing {
        let rank: Int
        let total: Int
        let pointsBehindLeader: Double  // 0 when the user is 1st
        let pointsToNextRank: Double    // 0 when the user is 1st
    }

    var standing: Standing? {
        let ranked = rankedParticipations
        guard let userID = UserSession.shared.userID,
              let myIdx = ranked.firstIndex(where: { $0.user.id == userID }) else { return nil }
        let me = ranked[myIdx]
        let leaderPoints = ranked.first?.totalPoints ?? me.totalPoints
        let toNext = myIdx > 0 ? ranked[myIdx - 1].totalPoints - me.totalPoints : 0
        return Standing(
            rank: me.rank,
            total: ranked.count,
            pointsBehindLeader: max(0, leaderPoints - me.totalPoints),
            pointsToNextRank: max(0, toNext)
        )
    }

    var daysRemaining: Int {
        let now = Date()
        guard challenge.status == .active else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: now, to: challenge.endDate).day ?? 0)
    }

    var countdownText: String {
        challenge.countdownText()
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
        // Capture the returned scores so we can inject them directly into the
        // UI without relying on a CloudKit read-after-write (which may miss
        // records that were just saved due to eventual consistency).
        //
        // We sync for completed challenges too, not just active ones. A completed
        // challenge is never touched by the home-screen sync, so any day that wasn't
        // synced while it was active (user didn't open the app that day, joined late,
        // or a back-dated challenge) would otherwise show 0 points forever. All of a
        // completed challenge's days are in the past, so syncChallenge backfills them
        // from HealthKit once and then no-ops on later opens (it skips days that
        // already have points).
        var mySyncedScores: [DailyScore] = []
        if challenge.status != .pending {
            mySyncedScores = await SyncCoordinator.shared.syncChallenge(challenge)
        }

        await fetchAndUpdate(syncedScores: mySyncedScores)

        // Load everyone's scores so the leaderboard shows real pts on first open,
        // not zeros (loadLeaderboard is otherwise only triggered by pull-to-refresh).
        await loadLeaderboard()

        await CloudKitManager.shared.registerSubscriptions(forActiveChallengeIDs: [challenge.id])

        // If we created this challenge but still aren't a participant, recover.
        let userID = UserSession.shared.userID ?? ""
        if challenge.creatorID == userID,
           !participations.contains(where: { $0.user.id == userID }) {
            Task {
                // First assume CloudKit propagation delay: wait, then refetch. This picks
                // up a participation that exists but hadn't replicated yet (just-created
                // challenge) without creating a duplicate.
                try? await Task.sleep(for: .seconds(3))
                await silentParticipationRefresh()
                // Still missing → the record genuinely doesn't exist (e.g. a challenge
                // created by an older build before auto-join was reliable). Recreate it
                // so the creator shows up on their own leaderboard.
                if !participations.contains(where: { $0.user.id == userID }) {
                    await recreateCreatorParticipation()
                }
            }
        }
    }

    /// Recreates the current user's participation when they're the creator but no
    /// participation record exists. Self-heals challenges whose auto-join never
    /// persisted. Injects the record locally too, since CloudKit read-after-write
    /// is not immediately consistent.
    @MainActor
    private func recreateCreatorParticipation() async {
        let userID = UserSession.shared.userID ?? ""
        guard let creator = UserSession.shared.currentUser,
              challenge.creatorID == userID,
              !participations.contains(where: { $0.user.id == userID }) else { return }

        let participation = Participation(
            // Deterministic id so recreating is an upsert, never a duplicate — even if
            // this runs more than once (e.g. two near-simultaneous opens).
            id: "\(challenge.id)_\(creator.id)",
            challengeID: challenge.id,
            user: creator,
            // joinedAt ≤ startDate so the creator is scored for the full challenge window.
            joinedAt: challenge.startDate,
            status: .active,
            hasAppleWatch: creator.hasAppleWatch
        )
        do {
            try await ck.saveParticipation(participation)
            participations.append(participation)
            ParticipationCache.save(participations, challengeID: challenge.id)
            NotificationCenter.default.post(name: .participationDidChange, object: nil)
        } catch {
            #if DEBUG
            print("[ChallengeDetail] recreateCreatorParticipation failed: \(error)")
            #endif
        }
    }

    @MainActor
    private func fetchAndUpdate(syncedScores: [DailyScore] = []) async {
        isLoading = participations.isEmpty  // spinner only when we have nothing to show
        error = nil
        defer { isLoading = false }

        do {
            var parts = try await ck.fetchParticipations(challengeID: challenge.id)

            let userID = UserSession.shared.userID ?? ""
            if let myPart = parts.first(where: { $0.user.id == userID }),
               let idx = parts.firstIndex(where: { $0.id == myPart.id }) {
                // Start with what CloudKit returned.
                var myScores = (try? await ck.fetchDailyScores(participationID: myPart.id)) ?? []

                // Merge with scores returned directly from the sync. These were computed
                // from HealthKit immediately before this fetch, so they are authoritative
                // for any day they cover. CloudKit eventual consistency means the fetch
                // above may not yet see records that were just saved — the direct sync
                // results fill that gap.
                for score in syncedScores {
                    if let existing = myScores.firstIndex(where: {
                        Calendar.current.isDate($0.date, inSameDayAs: score.date)
                    }) {
                        myScores[existing] = score  // prefer freshly computed
                    } else {
                        myScores.append(score)
                    }
                }

                parts[idx].dailyScores = myScores.sorted { $0.date < $1.date }
            }

            participations = parts
            lastFetchDate = Date()

            // Overlay today's ring data with a live HealthKit read for the current user.
            // CloudKit sync is async and may lag; this ensures the rings always show real
            // data immediately — matching exactly what the home-screen Activity card shows.
            if challenge.status == .active {
                await overlayLiveHealthKitData()
            }

            // Save AFTER the overlay so the cache includes real ring values.
            // On the next open the cached data shows instantly (non-zero rings)
            // while the fresh overlay runs in the background.
            ParticipationCache.save(participations, challengeID: challenge.id)
        } catch {
            let ck = error as? CKError
            #if DEBUG
            print("[ChallengeDetail] fetchAndUpdate failed: code=\(ck?.code.rawValue as Any) \(error.localizedDescription)")
            #endif
            if ck?.code == .networkUnavailable || ck?.code == .networkFailure {
                if participations.isEmpty { self.error = "No internet connection." }
            } else {
                self.error = "Couldn't load. Pull down to try again."
            }
        }
    }

    // MARK: - Live HealthKit overlay

    /// Reads HealthKit directly for today and injects the result into the current user's
    /// in-memory DailyScore so the rings always reflect live activity data, regardless of
    /// whether the CloudKit sync has completed. Mirrors the logic in HomeViewModel.loadRings().
    @MainActor
    private func overlayLiveHealthKitData() async {
        guard let userID = UserSession.shared.userID,
              let myIdx = participations.firstIndex(where: { $0.user.id == userID })
        else { return }

        // Use the live Watch status from UserDefaults — the same source the home screen
        // activity card uses, updated by WatchDetector on every home load.
        // participation.hasAppleWatch was stamped at join time and can be stale
        // (e.g. user paired a Watch after joining the challenge).
        let hasWatch = UserDefaults.standard.bool(forKey: "hasAppleWatch")
        let fetcher  = ActivityDataFetcher()
        let today    = Date()
        let cal      = Calendar.current

        // Read all metrics via individual HKStatisticsQuery / HKSampleQuery calls.
        // The Watch writes both individual samples and consolidated summaries to HealthKit;
        // individual samples sync within minutes, so we get live data immediately without
        // waiting for the Watch to push its end-of-day consolidated summary.
        let goalResolver = GoalResolver()
        async let stepsTask    = fetcher.steps(on: today)
        async let energyTask   = fetcher.activeEnergy(on: today)
        async let exerciseTask = fetcher.exerciseMinutes(on: today)
        async let standTask    = fetcher.standHours(on: today)
        async let distanceTask = fetcher.distanceMeters(on: today)
        let (steps, energy, exercise, stand, distance) =
            await (stepsTask ?? 0, energyTask ?? 0, exerciseTask ?? 0, standTask ?? 0, distanceTask ?? 0)

        var updatedRingData: RingData
        var points: Double

        if hasWatch {
            let moveGoal = await goalResolver.moveGoal()
            (points, updatedRingData) = PointsCalculator.calculateWatch(
                moveCalories: energy, moveGoal: moveGoal,
                exerciseMinutes: exercise,
                standHours: stand
            )
        } else {
            (points, updatedRingData) = PointsCalculator.calculateNonWatch(
                steps: steps, stepsGoal: goalResolver.stepsGoal,
                activeEnergy: energy, activeEnergyGoal: goalResolver.activeEnergyGoal,
                exerciseMinutes: exercise
            )
        }
        updatedRingData.totalSteps     = steps
        updatedRingData.distanceMeters = distance

        // Safety guard: if HealthKit returned all-zeros (Watch not yet synced, or
        // authorization denied for individual types), keep the existing CloudKit data
        // intact rather than clobbering valid scores with zeros.
        let existingPoints = participations[myIdx].dailyScores.first(where: {
            cal.isDate($0.date, inSameDayAs: today)
        })?.points ?? 0
        guard points > 0 || existingPoints == 0 else { return }

        // Update the existing today score, or insert a new in-memory one.
        let noonUTC = DailyScore.noonUTC(for: today)
        if let scoreIdx = participations[myIdx].dailyScores.firstIndex(where: {
            cal.isDate($0.date, inSameDayAs: today)
        }) {
            participations[myIdx].dailyScores[scoreIdx].ringData = updatedRingData
            participations[myIdx].dailyScores[scoreIdx].points   = points
        } else {
            let newScore = DailyScore(
                id: DailyScore.makeID(participationID: participations[myIdx].id, date: today),
                participationID: participations[myIdx].id,
                challengeID: challenge.id,
                date: noonUTC,
                points: points,
                ringData: updatedRingData,
                lastSyncedAt: today
            )
            participations[myIdx].dailyScores.append(newScore)
        }

        // Push the overlay result to CloudKit so the home screen's CloudKit-based
        // refresh picks up the current score rather than the older sync snapshot.
        // The sync only runs on detail open and captures activity at that moment;
        // the overlay has fresher data and should win.
        if let updated = participations[myIdx].dailyScores.first(where: {
            cal.isDate($0.date, inSameDayAs: today)
        }) {
            Task { try? await CloudKitManager.shared.saveDailyScores([updated]) }
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
            if challenge.status == .active {
                await overlayLiveHealthKitData()
            }
            ParticipationCache.save(participations, challengeID: challenge.id)
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
            let myUserID  = UserSession.shared.userID ?? ""
            let allScores = try await ck.fetchDailyScores(challengeID: challenge.id)
            for i in participations.indices {
                let ckScores = allScores
                    .filter { $0.participationID == participations[i].id }
                    .sorted { $0.date < $1.date }

                if participations[i].user.id == myUserID {
                    // For the current user, prefer the scores already in-memory: they were
                    // fetched immediately after syncChallenge wrote them to CloudKit, so they
                    // are more up-to-date than this leaderboard fetch which may hit a replica
                    // that hasn't yet seen the write (CloudKit eventual consistency).
                    // Merge: add any scores CloudKit has that we don't (other devices), but
                    // keep our version for any day we already have data for.
                    var merged = participations[i].dailyScores
                    for ckScore in ckScores {
                        let alreadyHave = merged.contains {
                            Calendar.current.isDate($0.date, inSameDayAs: ckScore.date)
                        }
                        if !alreadyHave { merged.append(ckScore) }
                    }
                    participations[i].dailyScores = merged.sorted { $0.date < $1.date }
                } else {
                    participations[i].dailyScores = ckScores
                }
            }
            leaderboardLoaded = true
            lastFetchDate = Date()
            // Clear any stale error banner now that the leaderboard loaded.
            self.error = nil

            // Re-apply the live HealthKit overlay to ensure today's rings are correct,
            // then persist so the cache has real ring values for the next open.
            if challenge.status == .active {
                await overlayLiveHealthKitData()
            }
            ParticipationCache.save(participations, challengeID: challenge.id)
        } catch {
            // Non-fatal — partial data is better than nothing; user can pull-to-refresh.
            #if DEBUG
            print("[ChallengeDetail] loadLeaderboard failed: code=\((error as? CKError)?.code.rawValue as Any) \(error.localizedDescription)")
            #endif
            self.error = "Couldn't load leaderboard. Pull down to try again."
        }
    }

    // MARK: - Refresh (pull-to-refresh reloads everything)

    @MainActor
    func refresh() async {
        leaderboardLoaded = false
        var mySyncedScores: [DailyScore] = []
        if challenge.status == .active {
            mySyncedScores = await SyncCoordinator.shared.syncChallenge(challenge)
        }
        await fetchAndUpdate(syncedScores: mySyncedScores)
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
            let myUserID = UserSession.shared.userID ?? ""
            let updatedScores = try await ck.fetchDailyScores(challengeID: challenge.id,
                                                               since: lastFetchDate)
            let today = Date()
            for score in updatedScores {
                guard let idx = participations.firstIndex(where: { $0.id == score.participationID }) else { continue }
                // Don't overwrite today's score for the current user — the HealthKit overlay
                // is always more accurate than a CloudKit push that may carry stale/zero values.
                let isMyTodayScore = participations[idx].user.id == myUserID
                                  && Calendar.current.isDate(score.date, inSameDayAs: today)
                if isMyTodayScore { continue }

                if let scoreIdx = participations[idx].dailyScores.firstIndex(where: { $0.id == score.id }) {
                    participations[idx].dailyScores[scoreIdx] = score
                } else {
                    participations[idx].dailyScores.append(score)
                    participations[idx].dailyScores.sort { $0.date < $1.date }
                }
            }
            lastFetchDate = Date()
        } catch {
            self.error = "Couldn't refresh scores. Pull down to try again."
        }
    }
}
