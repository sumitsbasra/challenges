import XCTest
@testable import Challenges

/// Whole-lap rings rest with their tip parked 0.04 laps past 12 o'clock (so the
/// overlap shadow reads); that pose is baked into the animation target so the tip
/// sweeps through 12 o'clock smoothly instead of snapping on the final frame.
final class ActivityRingRestPoseTests: XCTestCase {
    func testRestPoseMapping() {
        XCTAssertEqual(ActivityRingView.restPose(for: 0.97), 0.97)   // under 100%: untouched
        XCTAssertEqual(ActivityRingView.restPose(for: 1.0), 1.04)    // whole laps park past 12
        XCTAssertEqual(ActivityRingView.restPose(for: 1.02), 1.04)   // hair past: same pose
        XCTAssertEqual(ActivityRingView.restPose(for: 1.3), 1.3)     // clear of the join: untouched
        XCTAssertEqual(ActivityRingView.restPose(for: 3.0), 3.04)
    }
}

final class DailyScoreTests: XCTestCase {

    // Timezones at the extremes: UTC+12/13 (Auckland), UTC+14 (Kiritimati),
    // UTC−11 (Pago Pago). Noon UTC is already the *next* local day at UTC+12
    // and beyond, which is exactly the case the UTC-calendar helpers exist for.
    private static let zones = ["Pacific/Auckland", "Pacific/Kiritimati",
                                "Pacific/Pago_Pago", "UTC"]

    private func calendar(_ zoneID: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zoneID)!
        return cal
    }

    private func score(date: Date, points: Double = 100) -> DailyScore {
        DailyScore(
            id: "p1_test",
            participationID: "p1",
            challengeID: "ch1",
            date: date,
            points: points,
            ringData: RingData(moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                               stepsPct: 0, activeEnergyPct: 0, syncSource: .watch),
            lastSyncedAt: Date()
        )
    }

    // MARK: - noonUTC

    func testNoonUTCEncodesTheLocalCalendarDay() {
        for zoneID in Self.zones {
            let cal = calendar(zoneID)
            let now = Date()
            let noon = DailyScore.noonUTC(for: now, localCalendar: cal)

            let localDay = cal.dateComponents([.year, .month, .day], from: now)
            let utcDay = DailyScore.utcCalendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: noon)

            XCTAssertEqual(utcDay.year,  localDay.year,  "year mismatch in \(zoneID)")
            XCTAssertEqual(utcDay.month, localDay.month, "month mismatch in \(zoneID)")
            XCTAssertEqual(utcDay.day,   localDay.day,   "day mismatch in \(zoneID)")
            XCTAssertEqual(utcDay.hour, 12, "not noon UTC in \(zoneID)")
            XCTAssertEqual(utcDay.minute, 0)
            XCTAssertEqual(utcDay.second, 0)
        }
    }

    // MARK: - isFor(localDay:)

    func testTodayScoreMatchesTodayInEveryTimezone() {
        for zoneID in Self.zones {
            let cal = calendar(zoneID)
            let now = Date()
            let todayScore = score(date: DailyScore.noonUTC(for: now, localCalendar: cal))
            XCTAssertTrue(todayScore.isFor(localDay: now, localCalendar: cal),
                          "today's score not recognized as today in \(zoneID)")

            let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
            XCTAssertFalse(todayScore.isFor(localDay: yesterday, localCalendar: cal),
                           "today's score matched yesterday in \(zoneID)")
        }
    }

    // MARK: - day(of:)

    func testDayBucketsSameLocalDayTogetherAndDifferentDaysApart() {
        for zoneID in Self.zones {
            let cal = calendar(zoneID)
            let now = Date()
            let a = DailyScore.noonUTC(for: now, localCalendar: cal)
            // Same local day, built from a different moment within it.
            let sameDayLater = cal.startOfDay(for: now).addingTimeInterval(60)
            let b = DailyScore.noonUTC(for: sameDayLater, localCalendar: cal)
            XCTAssertEqual(DailyScore.day(of: a), DailyScore.day(of: b),
                           "same local day bucketed apart in \(zoneID)")

            let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
            let c = DailyScore.noonUTC(for: tomorrow, localCalendar: cal)
            XCTAssertNotEqual(DailyScore.day(of: a), DailyScore.day(of: c),
                              "different local days bucketed together in \(zoneID)")
        }
    }

    // MARK: - localDayStart

    func testLocalDayStartIsLocalMidnightOfEncodedDay() {
        for zoneID in Self.zones {
            let cal = calendar(zoneID)
            let now = Date()
            let s = score(date: DailyScore.noonUTC(for: now, localCalendar: cal))
            XCTAssertEqual(s.localDayStart(in: cal), cal.startOfDay(for: now),
                           "localDayStart is not local midnight in \(zoneID)")
        }
    }
}
