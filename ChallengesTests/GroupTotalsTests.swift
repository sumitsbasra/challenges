import XCTest
@testable import Challenges

final class GroupTotalsTests: XCTestCase {

    private func score(participationID: String, day: Date, points: Double,
                       steps: Double, meters: Double) -> DailyScore {
        var ring = RingData(moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                            stepsPct: 0, activeEnergyPct: 0, syncSource: .watch)
        ring.totalSteps = steps
        ring.distanceMeters = meters
        return DailyScore(
            id: "\(participationID)_\(day.timeIntervalSince1970)_\(points)",
            participationID: participationID,
            challengeID: "ch1",
            date: DailyScore.noonUTC(for: day),
            points: points,
            ringData: ring,
            lastSyncedAt: Date()
        )
    }

    private func participation(id: String, name: String, scores: [DailyScore]) -> Participation {
        var p = Participation(
            id: id,
            challengeID: "ch1",
            user: AppUser(id: "u-\(id)", displayName: name, appleUserID: "", hasAppleWatch: true),
            joinedAt: Date(),
            status: .active,
            hasAppleWatch: true
        )
        p.dailyScores = scores
        return p
    }

    private func workout(participationID: String, uuid: String) -> WorkoutSummary {
        WorkoutSummary(
            id: "\(participationID)_\(uuid)", participationID: participationID,
            challengeID: "ch1", name: "Running", systemImage: "figure.run",
            date: Date(), duration: 1800, activeEnergy: 300, distance: 5000
        )
    }

    func testSumsStepsDistanceAndWorkoutsPerParticipant() {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let parts = [
            participation(id: "p1", name: "Sumit", scores: [
                score(participationID: "p1", day: yesterday, points: 300, steps: 8_000, meters: 6_000),
                score(participationID: "p1", day: today,     points: 450, steps: 12_000, meters: 9_500),
            ]),
            participation(id: "p2", name: "Emily", scores: [
                score(participationID: "p2", day: today, points: 200, steps: 5_000, meters: 4_000),
            ]),
        ]
        let workouts = [
            workout(participationID: "p1", uuid: "a"),
            workout(participationID: "p1", uuid: "b"),
            workout(participationID: "p2", uuid: "c"),
        ]

        let result = ChallengeDetailViewModel.contributions(participations: parts, workouts: workouts)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].steps, 20_000)
        XCTAssertEqual(result[0].distanceMeters, 15_500)
        XCTAssertEqual(result[0].workouts, 2)
        XCTAssertEqual(result[1].steps, 5_000)
        XCTAssertEqual(result[1].workouts, 1)
    }

    func testDuplicateDayCountsOnceUsingHighestPointsRecord() {
        // Two records for the same day (save retry): only the higher-points one counts.
        let today = Date()
        let parts = [
            participation(id: "p1", name: "Sumit", scores: [
                score(participationID: "p1", day: today, points: 200, steps: 4_000, meters: 3_000),
                score(participationID: "p1", day: today, points: 450, steps: 9_000, meters: 7_000),
            ]),
        ]

        let result = ChallengeDetailViewModel.contributions(participations: parts, workouts: [])

        XCTAssertEqual(result[0].steps, 9_000, "duplicate day must not double-count")
        XCTAssertEqual(result[0].distanceMeters, 7_000)
    }

    func testParticipantWithNoScoresOrWorkoutsContributesZero() {
        let parts = [participation(id: "p1", name: "Emily", scores: [])]
        let result = ChallengeDetailViewModel.contributions(participations: parts, workouts: [])
        XCTAssertEqual(result[0].steps, 0)
        XCTAssertEqual(result[0].distanceMeters, 0)
        XCTAssertEqual(result[0].workouts, 0)
    }
}
