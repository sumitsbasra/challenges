import XCTest
@testable import Challenges

final class ChallengeCountdownTests: XCTestCase {

    private var calendar: Calendar { .current }

    private func makeChallenge(start: Date, end: Date, status: ChallengeStatus) -> Challenge {
        Challenge(id: "ch1", title: "Test", creatorID: "u1",
                  startDate: start, endDate: end, status: status,
                  inviteCode: "ABC123", createdAt: start)
    }

    private func day(_ offset: Int, from now: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    func testStartsTodayWhenStartIsToday() {
        let now = Date()
        let c = makeChallenge(start: day(0, from: now), end: day(7, from: now), status: .pending)
        XCTAssertEqual(c.startCountdownText(now: now), "Starts today")
    }

    func testStartsTomorrowWhenStartIsNextDay() {
        let now = Date()
        let c = makeChallenge(start: day(1, from: now), end: day(8, from: now), status: .pending)
        XCTAssertEqual(c.startCountdownText(now: now), "Starts tomorrow")
    }

    func testStartsInNDaysForTwoPlusDaysOut() {
        let now = Date()
        let c = makeChallenge(start: day(3, from: now), end: day(10, from: now), status: .pending)
        XCTAssertEqual(c.startCountdownText(now: now), "Starts in 3 days")
    }

    func testDaysUntilStartClampsAtZeroForPastStart() {
        let now = Date()
        let c = makeChallenge(start: day(-2, from: now), end: day(5, from: now), status: .active)
        XCTAssertEqual(c.daysUntilStart(now: now), 0)
        XCTAssertEqual(c.startCountdownText(now: now), "Starts today")
    }

    func testCountdownTextPendingDelegatesToStartCountdown() {
        let now = Date()
        let c = makeChallenge(start: day(2, from: now), end: day(9, from: now), status: .pending)
        XCTAssertEqual(c.countdownText(now: now), "Starts in 2 days")
    }

    func testCountdownTextActiveEndsToday() {
        let now = Date()
        let c = makeChallenge(start: day(-3, from: now), end: now, status: .active)
        XCTAssertEqual(c.countdownText(now: now), "Ends today")
    }

    func testCountdownTextActiveOngoing() {
        let now = Date()
        let c = makeChallenge(start: day(-3, from: now), end: day(5, from: now), status: .active)
        XCTAssertEqual(c.countdownText(now: now), "Ongoing")
    }

    func testCountdownTextCompleted() {
        let now = Date()
        let c = makeChallenge(start: day(-10, from: now), end: day(-3, from: now), status: .completed)
        XCTAssertEqual(c.countdownText(now: now), "Completed")
    }
}
