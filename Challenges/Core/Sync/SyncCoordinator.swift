import Foundation
import HealthKit


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
    func syncChallenge(_ challenge: Challenge) async {
        guard let userID = UserSession.shared.userID else { return }
        await syncChallenge(challenge, userID: userID)
    }

    /// Sync all active challenges for the current user.
    func syncCurrentChallenges() async {
        guard let userID = UserSession.shared.userID else { return }
        let ck = await MainActor.run { CloudKitManager.shared }

        do {
            let allChallenges = try await ck.fetchChallenges(forUserID: userID)
            let active = allChallenges.filter { $0.status == .active }
            await transitionPendingChallenges(allChallenges)

            for challenge in active {
                await syncChallenge(challenge, userID: userID)
            }

            await updateWidgetState(userID: userID, activeChallenges: active)
        } catch {
            #if DEBUG
            print("[SyncCoordinator] Failed to fetch challenges: \(error)")
            #endif
        }
    }

    // MARK: - Per-challenge sync

    private func syncChallenge(_ challenge: Challenge, userID: String) async {
        let ck = await MainActor.run { CloudKitManager.shared }
        // Find the current user's participation record.
        guard let participation = try? await ck.fetchParticipations(challengeID: challenge.id)
            .first(where: { $0.user.id == userID && $0.status == .active })
        else { return }

        let hasWatch = participation.hasAppleWatch
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
                #if DEBUG
                print("[SyncCoordinator] date(byAdding:) returned nil for \(day) — stopping day enumeration")
                #endif
                break
            }
            day = nextDay
        }

        // Fetch activity data and compute scores concurrently per day.
        var scores: [DailyScore] = []

        if hasWatch {
            let summaries = await fetcher.activitySummaries(from: startDay, to: endDay)
            let goalResolver = GoalResolver()
            let moveGoal = await goalResolver.moveGoal()

            for day in days {
                let summary = summaries[day]
                let moveCalories = summary?.activeEnergyBurned.doubleValue(for: .kilocalorie()) ?? 0
                let exerciseMins = summary?.appleExerciseTime.doubleValue(for: .minute()) ?? 0
                let standHours   = summary?.appleStandHours.doubleValue(for: .count()) ?? 0

                async let stepsTask    = fetcher.steps(on: day)
                async let distanceTask = fetcher.distanceMeters(on: day)
                let (steps, distance)  = await (stepsTask, distanceTask)

                var (points, ringData) = PointsCalculator.calculateWatch(
                    moveCalories: moveCalories, moveGoal: moveGoal,
                    exerciseMinutes: exerciseMins,
                    standHours: standHours
                )
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
        } else {
            let goalResolver = GoalResolver()

            for day in days {
                async let stepsTask    = fetcher.steps(on: day)
                async let energyTask   = fetcher.activeEnergy(on: day)
                async let exerciseTask = fetcher.exerciseMinutes(on: day)
                async let distanceTask = fetcher.distanceMeters(on: day)
                let (steps, energy, exercise, distance) = await (stepsTask, energyTask, exerciseTask, distanceTask)

                let stepsGoal    = goalResolver.stepsGoal
                let energyGoal   = goalResolver.activeEnergyGoal
                var (points, ringData) = PointsCalculator.calculateNonWatch(
                    steps: steps, stepsGoal: stepsGoal,
                    activeEnergy: energy, activeEnergyGoal: energyGoal,
                    exerciseMinutes: exercise
                )
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
        }

        // Batch upsert to CloudKit.
        do {
            try await ck.saveDailyScores(scores)
        } catch {
            #if DEBUG
            print("[SyncCoordinator] Failed to save scores for challenge \(challenge.id): \(error)")
            #endif
        }
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
        guard let topChallenge = activeChallenges.first else { return }
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
            #if DEBUG
            print("[SyncCoordinator] updateWidgetState failed for challenge \(topChallenge.id): \(error)")
            #endif
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
                #if DEBUG
                print("[SyncCoordinator] Status transition \(challenge.id) → \(status) failed (attempt \(attempt)): \(error)")
                #endif
                if attempt <= maxRetries {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                } else {
                    #if DEBUG
                    print("[SyncCoordinator] Status transition \(challenge.id) → \(status) failed after \(maxRetries + 1) attempts — giving up.")
                    #endif
                }
            }
        }
    }
}
