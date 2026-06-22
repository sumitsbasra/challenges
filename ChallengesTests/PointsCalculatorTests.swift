import XCTest
@testable import Challenges

final class PointsCalculatorTests: XCTestCase {

    private let accuracy = 0.0001

    // Apple Activity Competition model: points = sum of ring percentages, capped at
    // 600/day. All three rings at exactly 100% = 300 points.

    // MARK: - Watch path

    func testWatchAllRingsAtGoalScore300() {
        let (points, ring) = PointsCalculator.calculateWatch(
            moveCalories: 300, moveGoal: 300,
            exerciseMinutes: 30, exerciseGoal: 30,
            standHours: 12, standGoal: 12
        )
        // 100% + 100% + 100% = 300 points.
        XCTAssertEqual(points, 300, accuracy: accuracy)
        XCTAssertEqual(ring.moveRingPct, 1.0, accuracy: accuracy)
        XCTAssertEqual(ring.syncSource, .watch)
    }

    func testWatchCapsAt600() {
        let (points, _) = PointsCalculator.calculateWatch(
            moveCalories: 99_999, moveGoal: 300,
            exerciseMinutes: 99_999, exerciseGoal: 30,
            standHours: 99_999, standGoal: 12
        )
        XCTAssertEqual(points, PointsCalculator.maxPointsPerDay, accuracy: accuracy)
    }

    func testWatchSingleRingCanReachTheCap() {
        // One ring far over goal can max out the day, mirroring Apple's total cap.
        let (points, _) = PointsCalculator.calculateWatch(
            moveCalories: 3_000, moveGoal: 300,   // 1000%
            exerciseMinutes: 0, exerciseGoal: 30,
            standHours: 0, standGoal: 12
        )
        XCTAssertEqual(points, PointsCalculator.maxPointsPerDay, accuracy: accuracy)
    }

    func testWatchHalfGoalsScore150() {
        let (points, _) = PointsCalculator.calculateWatch(
            moveCalories: 150, moveGoal: 300,
            exerciseMinutes: 15, exerciseGoal: 30,
            standHours: 6, standGoal: 12
        )
        // 50% + 50% + 50% = 150.
        XCTAssertEqual(points, 150, accuracy: accuracy)
    }

    func testWatchZeroActivityScoresZero() {
        let (points, _) = PointsCalculator.calculateWatch(
            moveCalories: 0, moveGoal: 300,
            exerciseMinutes: 0, exerciseGoal: 30,
            standHours: 0, standGoal: 12
        )
        XCTAssertEqual(points, 0, accuracy: accuracy)
    }

    func testWatchZeroGoalDoesNotDivideByZeroOrExplode() {
        let (points, ring) = PointsCalculator.calculateWatch(
            moveCalories: 0.5, moveGoal: 0,
            exerciseMinutes: 0, exerciseGoal: 0,
            standHours: 0, standGoal: 0
        )
        XCTAssertFalse(points.isNaN)
        XCTAssertFalse(points.isInfinite)
        // max(goal, 1) guards the divisor → 0.5 / 1 = 50%.
        XCTAssertEqual(points, 50, accuracy: accuracy)
        XCTAssertEqual(ring.moveRingPct, 0.5, accuracy: accuracy)
    }

    // MARK: - Non-Watch path

    func testNonWatchAllMetricsAtGoalScore300() {
        let (points, ring) = PointsCalculator.calculateNonWatch(
            steps: 10_000, stepsGoal: 10_000,
            activeEnergy: 500, activeEnergyGoal: 500,
            exerciseMinutes: 30, exerciseGoal: 30
        )
        XCTAssertEqual(points, 300, accuracy: accuracy)
        XCTAssertEqual(ring.syncSource, .iphone)
        XCTAssertEqual(ring.stepsPct, 1.0, accuracy: accuracy)
    }

    func testNonWatchCapsAt600() {
        let (points, _) = PointsCalculator.calculateNonWatch(
            steps: 1_000_000, stepsGoal: 10_000,
            activeEnergy: 1_000_000, activeEnergyGoal: 500,
            exerciseMinutes: 1_000_000, exerciseGoal: 30
        )
        XCTAssertEqual(points, PointsCalculator.maxPointsPerDay, accuracy: accuracy)
    }

    func testNonWatchHalfGoalsScore150() {
        let (points, _) = PointsCalculator.calculateNonWatch(
            steps: 5_000, stepsGoal: 10_000,
            activeEnergy: 250, activeEnergyGoal: 500,
            exerciseMinutes: 15, exerciseGoal: 30
        )
        XCTAssertEqual(points, 150, accuracy: accuracy)
    }
}
