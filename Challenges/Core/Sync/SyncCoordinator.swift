import Foundation
import HealthKit
import OSLog


/// Orchestrates the core app loop:
///   1. Fetch activity data from HealthKit for each day of active challenges.
///   2. Calculate points using PointsCalculator.
///   3. Upsert DailyScore records to CloudKit.
///
/// Runs on a background actor to avoid blocking the main thread.
actor SyncCoordinator {

    static let shared = SyncCoordinator()

    private let fetcher = ActivityDataFetcher()
    private let watchDetector = WatchDetector()

    private init() {}

    // MARK: - Public API

    /// Sync a single challenge — used by the detail view to get fresh scores on open.
    /// Returns the current user's full score set (existing + freshly computed) so the
    /// caller can inject them directly without a follow-up CloudKit fetch.
    @discardableResult
    func syncChallenge(_ challenge: Challenge) async -> [DailyScore] {
        guard let userID = UserSession.shared.userID else { return [] }
        return await syncChallenge(challenge, userID: userID)
    }

    /// Sync all active challenges for the current user.
    /// Returns a map of challengeID → merged DailyScores (existing + freshly computed)
    /// so the caller can update its UI without a follow-up CloudKit fetch.
    @discardableResult
    func syncCurrentChallenges() async -> [String: [DailyScore]] {
        guard let userID = UserSession.shared.userID else { return [:] }
        let ck = await MainActor.run { CloudKitManager.shared }

        do {
            let allChallenges = try await ck.fetchChallenges(forUserID: userID)
            let active = allChallenges.filter { $0.status == .active }
            await transitionPendingChallenges(allChallenges)

            // Sync all active challenges concurrently and collect results.
            var results: [String: [DailyScore]] = [:]
            await withTaskGroup(of: (String, [DailyScore]).self) { group in
                for challenge in active {
                    group.addTask {
                        (challenge.id, await self.syncChallenge(challenge, userID: userID))
                    }
                }
                for await (id, scores) in group {
                    results[id] = scores
                }
            }

            await updateWidgetState(userID: userID, activeChallenges: active)
            return results
        } catch {
            // A cancelled fetch (view/task torn down) is benign — don't log it as an error.
            if !error.isCancellation {
                Logger.sync.error("Failed to fetch challenges: \(error.localizedDescription, privacy: .public)")
            }
            return [:]
        }
    }

    // MARK: - Per-challenge sync

    private func syncChallenge(_ challenge: Challenge, userID: String) async -> [DailyScore] {
        let ck = await MainActor.run { CloudKitManager.shared }
        // Find the current user's participation record.
        guard let participation = try? await ck.fetchParticipations(challengeID: challenge.id)
            .first(where: { $0.user.id == userID && $0.status == .active })
        else { return [] }

        // Use the live Watch status from UserDefaults — this is updated by WatchDetector
        // on every home screen load and matches what the home screen activity card shows.
        // participation.hasAppleWatch was stamped at join time and may be stale (e.g. the
        // user paired a Watch after joining, or HealthKit auth ran before Watch detection).
        let hasWatch = UserDefaults.standard.bool(forKey: "hasAppleWatch")

        // Backfill the display name onto the participation record so that other
        // participants can show this user's name even if the Users record is
        // not readable due to CloudKit security role restrictions.
        if let displayName = UserSession.shared.currentUser?.displayName {
            await ck.backfillDisplayNameIfNeeded(participationID: participation.id,
                                                 displayName: displayName)
        }

        let calendar = Calendar.current
        let today    = calendar.startOfDay(for: Date())
        // Late joiners start scoring from their join date, not the challenge start date.
        let effectiveStart = max(challenge.startDate, participation.joinedAt)
        let startDay = calendar.startOfDay(for: effectiveStart)
        let endDay   = min(today, calendar.startOfDay(for: challenge.endDate))

        // Collect all days in the competition window.
        var days: [Date] = []
        var day = startDay
        while day <= endDay {
            days.append(day)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
                Logger.sync.error("date(byAdding:) returned nil for \(day, privacy: .public) — stopping day enumeration")
                break
            }
            day = nextDay
        }

        // Determine which days actually need a HealthKit → CloudKit sync.
        //
        // Past days with a non-zero score already in CloudKit are left untouched.
        // Re-querying HealthKit for a past day can return 0 if the Watch hasn't
        // re-pushed that day's summary to the iPhone yet (e.g. first sync in the
        // morning), which would overwrite correct historical data with zeros.
        //
        // Rules:
        //   • Today  → always sync (activity is still accumulating).
        //   • Past day, no CloudKit record → sync (backfill for new joiners / first open).
        //   • Past day, CloudKit record with 0 pts → sync (may have been incomplete).
        //   • Past day, CloudKit record with pts > 0 → skip (trust the stored value).
        // Sync this user's workouts for the window so other participants can see them.
        // Runs independently of the day-score sync below (workouts exist even on days
        // whose score is already settled). Deterministic ids make this an upsert.
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let hkWorkouts = await fetcher.workouts(from: startDay, to: windowEnd)
        let workoutSummaries = hkWorkouts.map {
            ActivityDataFetcher.summary(from: $0, participationID: participation.id, challengeID: challenge.id)
        }
        if !workoutSummaries.isEmpty {
            try? await ck.saveWorkouts(workoutSummaries)
        }

        let existingScores = (try? await ck.fetchDailyScores(participationID: participation.id)) ?? []
        let existingByID = Dictionary(existingScores.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        let daysToSync = days.filter { day in
            guard !calendar.isDateInToday(day) else { return true }   // always sync today
            let scoreID = DailyScore.makeID(participationID: participation.id, date: day)
            return existingByID[scoreID].map { $0.points == 0 } ?? true  // missing or zero → sync
        }

        guard !daysToSync.isEmpty else { return existingScores }

        // Fetch activity data and compute scores for each day.
        //
        // We always use individual HKStatisticsQuery / HKSampleQuery calls regardless
        // of whether the user has a Watch. The Apple Watch writes both individual
        // quantity/category samples AND consolidated HKActivitySummary objects to
        // HealthKit — individual samples sync to iPhone within minutes of activity,
        // making them faster and more reliable than waiting for the consolidated summary.
        //
        // Watch vs. non-Watch only affects the *scoring model*:
        //   Watch   → calculateWatch  (Move/Exercise/Stand rings, personalized move goal)
        //   no Watch → calculateNonWatch (Steps + Active Energy + Exercise)
        let goalResolver = GoalResolver()
        // Fetch the Watch move goal once, outside the day loop — it's the same for all days.
        let moveGoal: Double = hasWatch ? await goalResolver.moveGoal() : 0

        var scores: [DailyScore] = []

        for day in daysToSync {
            async let stepsTask    = fetcher.steps(on: day)
            async let energyTask   = fetcher.activeEnergy(on: day)
            async let exerciseTask = fetcher.exerciseMinutes(on: day)
            async let standTask    = fetcher.standHours(on: day)
            async let distanceTask = fetcher.distanceMeters(on: day)
            let (stepsOpt, energyOpt, exerciseOpt, standOpt, distanceOpt) =
                await (stepsTask, energyTask, exerciseTask, standTask, distanceTask)

            // A nil from a fetcher means HealthKit errored (not a genuine zero).
            // For a *past* day being backfilled, if every metric failed to read,
            // skip it rather than persisting a bogus 0 that would stick (past days
            // with pts > 0 are never re-synced). Today always re-syncs, so a transient
            // failure there self-heals on the next sync.
            let allFailed = stepsOpt == nil && energyOpt == nil
                && exerciseOpt == nil && standOpt == nil
            if allFailed && !calendar.isDateInToday(day) { continue }

            let steps    = stepsOpt    ?? 0
            let energy   = energyOpt   ?? 0
            let exercise = exerciseOpt ?? 0
            let stand    = standOpt    ?? 0
            let distance = distanceOpt ?? 0

            var points: Double
            var ringData: RingData
            if hasWatch {
                // For past days, also try HKActivitySummary — it stores the Watch's
                // consolidated daily record and often has data when individual samples
                // haven't yet synced from Watch to iPhone (e.g. after a restore or
                // re-install). It also carries the personalized move goal for that
                // specific historical day, which may differ from today's goal.
                let isPastDay = !calendar.isDateInToday(day)
                let summaryEnergy:   Double
                let summaryExercise: Double
                let summaryStand:    Double
                let summaryMoveGoal: Double

                if isPastDay, let summary = await fetcher.activitySummary(on: day) {
                    summaryEnergy   = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                    summaryExercise = summary.appleExerciseTime.doubleValue(for: .minute())
                    summaryStand    = summary.appleStandHours.doubleValue(for: .count())
                    summaryMoveGoal = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                } else {
                    summaryEnergy   = 0
                    summaryExercise = 0
                    summaryStand    = 0
                    summaryMoveGoal = 0
                }

                // Prefer individual-query values; fall back to summary when individual is 0.
                // Individual queries are more real-time for today; summaries are more
                // reliable for historical days where samples may not have synced yet.
                let effectiveEnergy   = energy   > 0 ? energy   : summaryEnergy
                let effectiveExercise = exercise > 0 ? exercise : summaryExercise
                let effectiveStand    = stand    > 0 ? stand    : summaryStand
                let effectiveMoveGoal = summaryMoveGoal > 0 ? summaryMoveGoal : moveGoal

                (points, ringData) = PointsCalculator.calculateWatch(
                    moveCalories: effectiveEnergy, moveGoal: effectiveMoveGoal,
                    exerciseMinutes: effectiveExercise,
                    standHours: effectiveStand
                )
            } else {
                (points, ringData) = PointsCalculator.calculateNonWatch(
                    steps: steps, stepsGoal: goalResolver.stepsGoal,
                    activeEnergy: energy, activeEnergyGoal: goalResolver.activeEnergyGoal,
                    exerciseMinutes: exercise
                )
            }
            ringData.totalSteps     = steps
            ringData.distanceMeters = distance

            let noonUTC = DailyScore.noonUTC(for: day)
            let scoreID = DailyScore.makeID(participationID: participation.id, date: day)
            scores.append(DailyScore(
                id: scoreID,
                participationID: participation.id,
                challengeID: challenge.id,
                date: noonUTC,
                points: points,
                ringData: ringData,
                lastSyncedAt: Date()
            ))
        }

        // Batch upsert to CloudKit.
        do {
            try await ck.saveDailyScores(scores)
        } catch {
            Logger.sync.error("Failed to save scores for challenge \(challenge.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        // Return the full picture: preserved existing scores (pts > 0, not re-synced)
        // merged with the freshly computed ones. The caller can inject these directly
        // into the UI without a follow-up CloudKit fetch, which is important because
        // CloudKit read-after-write consistency is not guaranteed — a fetch immediately
        // after a save may miss the new records.
        let resyncedIDs = Set(scores.map { $0.id })
        let preserved   = existingScores.filter { !resyncedIDs.contains($0.id) }
        return preserved + scores
    }

    // MARK: - Challenge lifecycle transitions

    /// Transitions pending challenges to active and active challenges to completed
    /// based on the current date. The first client to open the app after a boundary
    /// performs the write; all others receive it via CloudKit subscription.
    private func transitionPendingChallenges(_ challenges: [Challenge]) async {
        let ck = await MainActor.run { CloudKitManager.shared }
        let now = Date()
        for challenge in challenges {
            if challenge.status == .pending && challenge.startDate <= now {
                await transitionStatus(of: challenge, to: .active, ck: ck)
            } else if challenge.status == .active && challenge.endDate < now {
                // endDate is always 23:59:59 on the final day, so this fires at midnight
                // after the last day — no arbitrary buffer needed.
                await transitionStatus(of: challenge, to: .completed, ck: ck)
            }
        }
    }

    // MARK: - Widget state

    /// Writes the top active challenge's rank and score to shared App Group UserDefaults
    /// so the widget can display current standings without a CloudKit fetch.
    private func updateWidgetState(userID: String, activeChallenges: [Challenge]) async {
        // `activeChallenges` comes from an unordered filter, so pick a stable "top"
        // challenge: the one ending soonest (most urgent), tie-broken by id. Without
        // this the widget could flip between challenges on successive syncs.
        let topChallenge = activeChallenges.min { lhs, rhs in
            if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
            return lhs.id < rhs.id
        }
        guard let topChallenge else {
            WidgetDataWriter.clear()
            return
        }
        let ck = await MainActor.run { CloudKitManager.shared }
        do {
            var participations = try await ck.fetchParticipations(challengeID: topChallenge.id)
            ScoreAggregator.aggregate(&participations)
            guard let mine = participations.first(where: { $0.user.id == userID }) else { return }
            let daysRemaining = max(0, Calendar.current.dateComponents([.day], from: Date(), to: topChallenge.endDate).day ?? 0)
            let state = WidgetState(
                challengeTitle: topChallenge.title,
                challengeID: topChallenge.id,
                rank: mine.rank,
                totalPoints: mine.totalPoints,
                daysRemaining: daysRemaining,
                participantCount: participations.count,
                updatedAt: Date()
            )
            WidgetDataWriter.write(state: state)
        } catch {
            Logger.sync.error("updateWidgetState failed for challenge \(topChallenge.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func transitionStatus(of challenge: Challenge, to status: ChallengeStatus,
                                  ck: CloudKitManager) async {
        let maxRetries = 2
        for attempt in 1...maxRetries + 1 {
            do {
                try await ck.updateChallengeStatus(challenge.id, status: status)
                return
            } catch {
                Logger.sync.error("Status transition \(challenge.id, privacy: .public) → \(status.rawValue, privacy: .public) failed (attempt \(attempt, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                if attempt <= maxRetries {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                } else {
                    Logger.sync.error("Status transition \(challenge.id, privacy: .public) → \(status.rawValue, privacy: .public) gave up after \(maxRetries + 1, privacy: .public) attempts")
                }
            }
        }
    }
}
