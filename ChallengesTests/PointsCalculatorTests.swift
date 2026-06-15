import XCTest
@testable import Challenges

final class PointsCalculatorTests: XCTestCase {

    private let accuracy = 0.0001

    // MARK: - Watch path

    func testWatchAllRingsAtGoalScoresFullDay() {
        let (points, ring) = PointsCalculator.calculateWatch(
            moveCalories: 300, moveGoal: 300,
            exerciseMinutes: 30, exerciseGoal: 30,
            standHours: 12, standGoal: 12
        )
        // Each ring at exactly 100% → average 1.0 → 600 points.
        XCTAssertEqual(points, PointsCalculator.maxPointsPerDay, accuracy: accuracy)
        XCTAssertEqual(ring.moveRingPct, 1.0, accuracy: accuracy)
        XCTAssertEqual(ring.exerciseRingPct, 1.0, accuracy: accuracy)
        XCTAssertEqual(ring.standRingPct, 1.0, accuracy: accuracy)
        XCTAssertEqual(ring.syncSource, .watch)
    }

    func testWatchContributionIsClampedAt200Percent() {
        let (points, ring) = PointsCalculator.calculateWatch(
            moveCalories: 99_999, moveGoal: 300,
            exerciseMinutes: 99_999, exerciseGoal: 30,
            standHours: 99_999, standGoal: 12
        )
        // Every ring clamps to 2.0, so the day caps at 2.0 * 600 = 1200.
        let expectedMax = PointsCalculator.maxContributionMultiplier * PointsCalculator.maxPointsPerDay
        XCTAssertEqual(points, expectedMax, accuracy: accuracy)
        XCTAssertEqual(ring.moveRingPct, PointsCalculator.maxContributionMultiplier, accuracy: accuracy)
        XCTAssertEqual(ring.exerciseRingPct, PointsCalculator.maxContributionMultiplier, accuracy: accuracy)
        XCTAssertEqual(ring.standRingPct, PointsCalculator.maxContributionMultiplier, accuracy: accuracy)
    }

    func testWatchZeroGoalDoesNotDivideByZeroOrExplode() {
        let (points, ring) = PointsCalculator.calculateWatch(
            moveCalories: 0.5, moveGoal: 0,
            exerciseMinutes: 0, exerciseGoal: 0,
            standHours: 0, standGoal: 0
        )
        // max(goal, 1) guards the divisor → 0.5 / 1 = 0.5 for move, others 0.
        XCTAssertFalse(points.isNaN)
        XCTAssertFalse(points.isInfinite)
        XCTAssertEqual(ring.moveRingPct, 0.5, accuracy: accuracy)
        XCTAssertEqual(ring.exerciseRingPct, 0.0, accuracy: accuracy)
    }

    func testWatchZeroActivityScoresZero() {
        let (points, _) = PointsCalculator.calculateWatch(
            moveCalories: 0, moveGoal: 300,
            exerciseMinutes: 0, exerciseGoal: 30,
            standHours: 0, standGoal: 12
        )
        XCTAssertEqual(points, 0, accuracy: accuracy)
    }

    // MARK: - Non-Watch path

    func testNonWatchAllMetricsAtGoalScoresFullDay() {
        let (points, ring) = PointsCalculator.calculateNonWatch(
            steps: 10_000, stepsGoal: 10_000,
            activeEnergy: 500, activeEnergyGoal: 500,
            exerciseMinutes: 30, exerciseGoal: 30
        )
        XCTAssertEqual(points, PointsCalculator.maxPointsPerDay, accuracy: accuracy)
        XCTAssertEqual(ring.syncSource, .iphone)
        XCTAssertEqual(ring.stepsPct, 1.0, accuracy: accuracy)
        XCTAssertEqual(ring.activeEnergyPct, 1.0, accuracy: accuracy)
    }

    func testNonWatchContributionIsClampedAt200Percent() {
        let (points, _) = PointsCalculator.calculateNonWatch(
            steps: 1_000_000, stepsGoal: 10_000,
            activeEnergy: 1_000_000, activeEnergyGoal: 500,
            exerciseMinutes: 1_000_000, exerciseGoal: 30
        )
        let expectedMax = PointsCalculator.maxContributionMultiplier * PointsCalculator.maxPointsPerDay
        XCTAssertEqual(points, expectedMax, accuracy: accuracy)
    }

    func testNonWatchHalfGoalsScoreHalf() {
        let (points, _) = PointsCalculator.calculateNonWatch(
            steps: 5_000, stepsGoal: 10_000,
            activeEnergy: 250, activeEnergyGoal: 500,
            exerciseMinutes: 15, exerciseGoal: 30
        )
        // Each metric at 0.5 → average 0.5 → half of a full day.
        XCTAssertEqual(points, PointsCalculator.maxPointsPerDay * 0.5, accuracy: accuracy)
    }
}
