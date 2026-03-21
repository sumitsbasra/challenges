import Foundation

/// Pure, stateless points calculator — no HealthKit or CloudKit imports.
/// All inputs are plain doubles so this is easy to unit test.
enum PointsCalculator {

    static let maxPointsPerDay: Double = 600
    static let maxContributionMultiplier: Double = 2.0  // 200% = max

    // MARK: - Watch path (3 rings)

    /// Calculate daily points for a user with an Apple Watch.
    ///
    /// - Parameters:
    ///   - moveCalories: Active energy burned today (kcal)
    ///   - moveGoal: User's personalized move goal (kcal)
    ///   - exerciseMinutes: Apple exercise minutes today
    ///   - exerciseGoal: Target exercise minutes (default 30)
    ///   - standHours: Stand hours credited today
    ///   - standGoal: Target stand hours (default 12)
    /// - Returns: Points (0–600) and ring data fractions.
    static func calculateWatch(
        moveCalories: Double, moveGoal: Double,
        exerciseMinutes: Double, exerciseGoal: Double = 30,
        standHours: Double, standGoal: Double = 12
    ) -> (points: Double, ringData: RingData) {
        let movePct  = clamp(moveCalories  / max(moveGoal, 1),     0, maxContributionMultiplier)
        let exPct    = clamp(exerciseMinutes / max(exerciseGoal, 1), 0, maxContributionMultiplier)
        let standPct = clamp(standHours    / max(standGoal, 1),    0, maxContributionMultiplier)

        let rawScore = (movePct + exPct + standPct) / 3.0
        let points = rawScore * maxPointsPerDay

        let ringData = RingData(
            moveRingPct: movePct,
            exerciseRingPct: exPct,
            standRingPct: standPct,
            stepsPct: 0,
            activeEnergyPct: 0,
            syncSource: .watch
        )
        return (points, ringData)
    }

    // MARK: - Non-Watch path (iPhone only, 2 metrics)

    /// Calculate daily points for a user without an Apple Watch.
    ///
    /// - Parameters:
    ///   - steps: Steps today
    ///   - stepsGoal: Target steps per day (default 10 000)
    ///   - activeEnergy: Active energy burned today (kcal)
    ///   - activeEnergyGoal: Target active energy (default 500 kcal)
    /// - Returns: Points (0–600) and ring data fractions.
    static func calculateNonWatch(
        steps: Double, stepsGoal: Double = 10_000,
        activeEnergy: Double, activeEnergyGoal: Double = 500
    ) -> (points: Double, ringData: RingData) {
        let stepsPct  = clamp(steps        / max(stepsGoal, 1),        0, maxContributionMultiplier)
        let energyPct = clamp(activeEnergy / max(activeEnergyGoal, 1), 0, maxContributionMultiplier)

        let rawScore = (stepsPct + energyPct) / 2.0
        let points = rawScore * maxPointsPerDay

        let ringData = RingData(
            moveRingPct: 0,
            exerciseRingPct: 0,
            standRingPct: 0,
            stepsPct: stepsPct,
            activeEnergyPct: energyPct,
            syncSource: .iphone
        )
        return (points, ringData)
    }

    // MARK: - Private helpers

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
