import XCTest
@testable import Challenges

final class ScoreAggregatorTests: XCTestCase {

    // MARK: - Helpers

    private func user(_ id: String, name: String? = nil) -> AppUser {
        AppUser(id: id, displayName: name ?? id, appleUserID: "apple-\(id)", hasAppleWatch: true)
    }

    private func day(_ offset: Int) -> Date {
        let base = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: offset, to: base)!
    }

    private func score(participationID: String, date: Date, points: Double) -> DailyScore {
        DailyScore(
            id: "\(participationID)_\(date.timeIntervalSince1970)_\(points)",
            participationID: participationID,
            challengeID: "ch1",
            date: date,
            points: points,
            ringData: RingData(moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                               stepsPct: 0, activeEnergyPct: 0, syncSource: .watch),
            lastSyncedAt: Date()
        )
    }

    private func participation(id: String, userID: String, joinedAt: Date,
                               scores: [DailyScore]) -> Participation {
        var p = Participation(id: id, challengeID: "ch1", user: user(userID),
                              joinedAt: joinedAt, status: .active, hasAppleWatch: true)
        p.dailyScores = scores
        return p
    }

    // MARK: - Totals

    func testTotalIsSumOfDistinctDays() {
        var parts = [participation(id: "p1", userID: "u1", joinedAt: day(-3), scores: [
            score(participationID: "p1", date: day(-2), points: 100),
            score(participationID: "p1", date: day(-1), points: 200),
            score(participationID: "p1", date: day(0),  points: 50),
        ])]
        ScoreAggregator.aggregate(&parts)
        XCTAssertEqual(parts[0].totalPoints, 350, accuracy: 0.0001)
    }

    func testDuplicateDayKeepsHighestScore() {
        // Two records for the same calendar day (e.g. from save retries) must not
        // double-count — the aggregator keeps the max per day.
        var parts = [participation(id: "p1", userID: "u1", joinedAt: day(-2), scores: [
            score(participationID: "p1", date: day(-1), points: 120),
            score(participationID: "p1", date: day(-1), points: 300),
        ])]
        ScoreAggregator.aggregate(&parts)
        XCTAssertEqual(parts[0].totalPoints, 300, accuracy: 0.0001)
    }

    func testFutureDatedScoresAreExcluded() {
        var parts = [participation(id: "p1", userID: "u1", joinedAt: day(-1), scores: [
            score(participationID: "p1", date: day(0),  points: 100),
            score(participationID: "p1", date: day(5),  points: 999), // future → ignored
        ])]
        ScoreAggregator.aggregate(&parts)
        XCTAssertEqual(parts[0].totalPoints, 100, accuracy: 0.0001)
    }

    // MARK: - Ranking

    func testRankingOrdersByPointsDescending() {
        var parts = [
            participation(id: "p1", userID: "u1", joinedAt: day(-3),
                          scores: [score(participationID: "p1", date: day(-1), points: 100)]),
            participation(id: "p2", userID: "u2", joinedAt: day(-3),
                          scores: [score(participationID: "p2", date: day(-1), points: 300)]),
            participation(id: "p3", userID: "u3", joinedAt: day(-3),
                          scores: [score(participationID: "p3", date: day(-1), points: 200)]),
        ]
        ScoreAggregator.aggregate(&parts)
        XCTAssertEqual(parts.map { $0.user.id }, ["u2", "u3", "u1"])
        XCTAssertEqual(parts.map { $0.rank }, [1, 2, 3])
    }

    func testTieBreaksByEarlierJoinThenUserID() {
        // Equal points: earlier joiner ranks higher; if joinedAt is equal too,
        // lexicographically smaller user id wins.
        let sharedScore = 150.0
        var parts = [
            participation(id: "pB", userID: "u_b", joinedAt: day(-1),
                          scores: [score(participationID: "pB", date: day(-1), points: sharedScore)]),
            participation(id: "pA", userID: "u_a", joinedAt: day(-3),
                          scores: [score(participationID: "pA", date: day(-1), points: sharedScore)]),
            participation(id: "pC", userID: "u_c", joinedAt: day(-1),
                          scores: [score(participationID: "pC", date: day(-1), points: sharedScore)]),
        ]
        ScoreAggregator.aggregate(&parts)
        // u_a joined earliest → rank 1. u_b and u_c joined same day → tie broken by id.
        XCTAssertEqual(parts.map { $0.user.id }, ["u_a", "u_b", "u_c"])
    }

    func testRankLookupHelper() {
        var parts = [
            participation(id: "p1", userID: "u1", joinedAt: day(-3),
                          scores: [score(participationID: "p1", date: day(-1), points: 100)]),
            participation(id: "p2", userID: "u2", joinedAt: day(-3),
                          scores: [score(participationID: "p2", date: day(-1), points: 300)]),
        ]
        ScoreAggregator.aggregate(&parts)
        XCTAssertEqual(ScoreAggregator.rank(of: "u2", in: parts), 1)
        XCTAssertEqual(ScoreAggregator.rank(of: "u1", in: parts), 2)
        XCTAssertNil(ScoreAggregator.rank(of: "nobody", in: parts))
    }

    func testRankedDoesNotMutateInput() {
        let parts = [
            participation(id: "p1", userID: "u1", joinedAt: day(-3),
                          scores: [score(participationID: "p1", date: day(-1), points: 100)]),
        ]
        _ = ScoreAggregator.ranked(parts)
        XCTAssertEqual(parts[0].totalPoints, 0, "ranked() must not mutate the original array")
        XCTAssertEqual(parts[0].rank, 0)
    }
}
