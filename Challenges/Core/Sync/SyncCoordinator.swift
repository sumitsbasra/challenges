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

    private let ck = CloudKitManager.shared
    private let fetcher = ActivityDataFetcher()
    private let watchDetector = WatchDetector()

    private init() {}

    // MARK: - Public API

    /// Sync all active challenges for the current user.
    func syncCurrentChallenges() async {
        guard let userID = await UserSession.shared.userID else { return }

        do {
            let allChallenges = try await ck.fetchChallenges(forUserID: userID)
            let active = allChallenges.filter { $0.status == .active }
            await transitionPendingChallenges(allChallenges)

            for challenge in active {
                await syncChallenge(challenge, userID: userID)
            }

            // Update the widget with the user's current rank in their most active challenge.
            await updateWidgetState(userID: userID, activeChallenges: active)
        } catch {
            print("[SyncCoordinator] Failed to fetch challenges: \(error)")
        }
    }

    // MARK: - Per-challenge sync

    private func syncChallenge(_ challenge: Challenge, userID: String) async {
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
            let goalResolver = await GoalResolver()
            let moveGoal = await goalResolver.moveGoal()

            for day in days {
                let summary = summaries[day]
                let moveCalories = summary?.activeEnergyBurned.doubleValue(for: .kilocalorie()) ?? 0
                let exerciseMins = summary?.appleExerciseTime.doubleValue(for: .minute()) ?? 0
                let standHours   = summary?.appleStandHoursGoal > 0
                    ? (summary?.appleStandHours.doubleValue(for: .count()) ?? 0)
                    : 0

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
            let goalResolver = await GoalResolver()

            for day in days {
                async let stepsTask   = fetcher.steps(on: day)
                async let energyTask  = fetcher.activeEnergy(on: day)
                let (steps, energy) = await (stepsTask, energyTask)

                let (points, ringData) = PointsCalculator.calculateNonWatch(
                    steps: steps, stepsGoal: goalResolver.stepsGoal,
                    activeEnergy: energy, activeEnergyGoal: goalResolver.activeEnergyGoal
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

    // MARK: - Widget state

    /// Computes the user's rank in their first active challenge and writes a
    /// WidgetState snapshot to the shared App Group UserDefaults.
    /// The widget reads this data without needing direct CloudKit access.
    private func updateWidgetState(userID: String, activeChallenges: [Challenge]) async {
        guard let challenge = activeChallenges.first else { return }

        do {
            var participations = try await ck.fetchParticipations(challengeID: challenge.id)
            let scores = try await ck.fetchDailyScores(challengeID: challenge.id)

            for i in participations.indices {
                participations[i].dailyScores = scores.filter {
                    $0.participationID == participations[i].id
                }
            }

            let ranked = ScoreAggregator.ranked(participations)
            guard let mine = ranked.first(where: { $0.user.id == userID }) else { return }

            let daysRemaining = max(0, Calendar.current.dateComponents(
                [.day], from: Date(), to: challenge.endDate
            ).day ?? 0)

            let state = WidgetState(
                challengeTitle: challenge.title,
                challengeID: challenge.id,
                rank: mine.rank,
                totalPoints: mine.totalPoints,
                daysRemaining: daysRemaining,
                participantCount: ranked.count,
                updatedAt: Date()
            )
            WidgetDataWriter.write(state: state)
        } catch {
            print("[SyncCoordinator] Widget state update failed: \(error)")
        }
    }

    // MARK: - Challenge lifecycle transitions

    /// Transitions pending challenges to active and active challenges to completed
    /// based on the current date. The first client to open the app after a boundary
    /// performs the write; all others receive it via CloudKit subscription.
    private func transitionPendingChallenges(_ challenges: [Challenge]) async {
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
