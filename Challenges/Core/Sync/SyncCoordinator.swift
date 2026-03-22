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

            // Widget state update requires WidgetDataWriter to be added to the app target.
            // await updateWidgetState(userID: userID, activeChallenges: active)
        } catch {
            print("[SyncCoordinator] Failed to fetch challenges: \(error)")
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
        let today = calendar.startOfDay(for: Date())
        let startDay = calendar.startOfDay(for: challenge.startDate)
        let endDay = min(today, calendar.startOfDay(for: challenge.endDate))

        // Collect all days in the competition window.
        var days: [Date] = []
        var day = startDay
        while day <= endDay {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
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

                let (points, ringData) = PointsCalculator.calculateWatch(
                    moveCalories: moveCalories, moveGoal: moveGoal,
                    exerciseMinutes: exerciseMins,
                    standHours: standHours
                )

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
                async let stepsTask   = fetcher.steps(on: day)
                async let energyTask  = fetcher.activeEnergy(on: day)
                let (steps, energy) = await (stepsTask, energyTask)

                let stepsGoal = goalResolver.stepsGoal
                let energyGoal = goalResolver.activeEnergyGoal
                let (points, ringData) = PointsCalculator.calculateNonWatch(
                    steps: steps, stepsGoal: stepsGoal,
                    activeEnergy: energy, activeEnergyGoal: energyGoal
                )

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
            print("[SyncCoordinator] Failed to save scores for challenge \(challenge.id): \(error)")
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
            do {
                if challenge.status == .pending && challenge.startDate <= now {
                    try await ck.updateChallengeStatus(challenge.id, status: .active)
                } else if challenge.status == .active && challenge.endDate.addingTimeInterval(24 * 3600) < now {
                    try await ck.updateChallengeStatus(challenge.id, status: .completed)
                }
            } catch {
                print("[SyncCoordinator] Status transition failed: \(error)")
            }
        }
    }
}
