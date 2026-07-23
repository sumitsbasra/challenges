import XCTest
@testable import Challenges

final class OvertakeMonitorTests: XCTestCase {

    private func participation(userID: String, name: String? = nil,
                               rank: Int, points: Double) -> Participation {
        var p = Participation(
            id: "p-\(userID)",
            challengeID: "ch1",
            user: AppUser(id: userID, displayName: name ?? userID,
                          appleUserID: "apple-\(userID)", hasAppleWatch: true),
            joinedAt: Date(),
            status: .active,
            hasAppleWatch: true
        )
        p.rank = rank
        p.totalPoints = points
        return p
    }

    func testDetectsDropAndNamesTheParticipantDirectlyAhead() {
        let standings = [
            participation(userID: "u1", name: "Maya", rank: 1, points: 900),
            participation(userID: "u2", name: "Jake", rank: 2, points: 700),
            participation(userID: "me",  name: "Sana", rank: 3, points: 650),
        ]
        let overtake = OvertakeMonitor.detect(previousRank: 2, standings: standings, userID: "me")
        XCTAssertEqual(overtake, .init(passerName: "Jake", pointsBehind: 50, newRank: 3))
    }

    func testNoOvertakeWhenRankImprovesOrHolds() {
        let standings = [
            participation(userID: "u1", name: "Maya", rank: 1, points: 900),
            participation(userID: "me",  name: "Sana", rank: 2, points: 700),
        ]
        XCTAssertNil(OvertakeMonitor.detect(previousRank: 2, standings: standings, userID: "me"))
        XCTAssertNil(OvertakeMonitor.detect(previousRank: 3, standings: standings, userID: "me"))
    }

    func testNoOvertakeOnFirstObservation() {
        // No stored rank yet (first sync of a challenge) — nothing to compare against.
        let standings = [
            participation(userID: "u1", rank: 1, points: 900),
            participation(userID: "me", rank: 2, points: 700),
        ]
        XCTAssertNil(OvertakeMonitor.detect(previousRank: nil, standings: standings, userID: "me"))
    }

    func testNoOvertakeWhenUserAbsentFromStandings() {
        let standings = [participation(userID: "u1", rank: 1, points: 900)]
        XCTAssertNil(OvertakeMonitor.detect(previousRank: 1, standings: standings, userID: "me"))
    }

    func testPointsBehindNeverNegative() {
        // Ranks can come from a tie-break where the passer has equal points.
        let standings = [
            participation(userID: "u1", name: "Maya", rank: 1, points: 700),
            participation(userID: "me",  name: "Sana", rank: 2, points: 700),
        ]
        let overtake = OvertakeMonitor.detect(previousRank: 1, standings: standings, userID: "me")
        XCTAssertEqual(overtake?.pointsBehind, 0)
    }

    func testTitleNamesPasserAndChallenge() {
        let overtake = OvertakeMonitor.Overtake(passerName: "Maya", pointsBehind: 43.4, newRank: 2)
        XCTAssertEqual(
            OvertakeMonitor.title(for: overtake, challengeTitle: "Road to NYC"),
            "Maya just passed you in Road to NYC"
        )
    }

    func testBodyStatesTheGap() {
        let overtake = OvertakeMonitor.Overtake(passerName: "Maya", pointsBehind: 43.4, newRank: 2)
        XCTAssertEqual(
            OvertakeMonitor.body(for: overtake),
            "You're 43 points behind, go get them!"
        )
    }

    // MARK: - Reaction IDs

    func testReactionIDIsStablePerSenderRecipientDay() {
        let now = Date()
        let a = Reaction.makeID(fromParticipationID: "pA", toParticipationID: "pB", date: now)
        let b = Reaction.makeID(fromParticipationID: "pA", toParticipationID: "pB", date: now)
        XCTAssertEqual(a, b, "same sender/recipient/day must upsert, not duplicate")

        let reversed = Reaction.makeID(fromParticipationID: "pB", toParticipationID: "pA", date: now)
        XCTAssertNotEqual(a, reversed, "direction matters")

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        let nextDay = Reaction.makeID(fromParticipationID: "pA", toParticipationID: "pB", date: tomorrow)
        XCTAssertNotEqual(a, nextDay, "a new day is a new reaction")
    }
}
