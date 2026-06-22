import Foundation

/// Pure, stateless points calculator — no HealthKit or CloudKit imports.
/// All inputs are plain doubles so this is easy to unit test.
enum PointsCalculator {

    /// Hard daily cap, matching Apple's Activity Competitions (max 600 points/day).
    static let maxPointsPerDay: Double = 600
    /// Upper bound used only when clamping ring *fractions* for display, so a single
    /// over-achieved ring doesn't render absurdly. It does not limit scoring — points
    /// use the raw percentages and are capped by `maxPointsPerDay`.
    static let maxContributionMultiplier: Double = 2.0

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
        // Apple Activity Competition scoring: points = the sum of each ring's
        // percentage, capped at 600/day. All three rings at 100% = 300 points; you
        // can earn more by exceeding goals, up to the 600 daily cap.
        let moveFrac  = moveCalories    / max(moveGoal, 1)
        let exFrac    = exerciseMinutes / max(exerciseGoal, 1)
        let standFrac = standHours      / max(standGoal, 1)

        let points = min(maxPointsPerDay, max(0, moveFrac + exFrac + standFrac) * 100)

        let ringData = RingData(
            moveRingPct: clamp(moveFrac, 0, maxContributionMultiplier),
            exerciseRingPct: clamp(exFrac, 0, maxContributionMultiplier),
            standRingPct: clamp(standFrac, 0, maxContributionMultiplier),
            stepsPct: 0,
            activeEnergyPct: 0,
            syncSource: .watch,
            moveCalories: moveCalories,
            moveGoal: moveGoal,
            exerciseMinutes: exerciseMinutes,
            exerciseGoal: exerciseGoal,
            standHours: standHours,
            standGoal: standGoal
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
        activeEnergy: Double, activeEnergyGoal: Double = 500,
        exerciseMinutes: Double, exerciseGoal: Double = 30
    ) -> (points: Double, ringData: RingData) {
        // Same Apple-style scoring as the Watch path: sum of percentages, capped at 600.
        let stepsFrac    = steps           / max(stepsGoal, 1)
        let energyFrac   = activeEnergy    / max(activeEnergyGoal, 1)
        let exerciseFrac = exerciseMinutes / max(exerciseGoal, 1)

        let points = min(maxPointsPerDay, max(0, stepsFrac + energyFrac + exerciseFrac) * 100)

        let stepsPct    = clamp(stepsFrac,    0, maxContributionMultiplier)
        let energyPct   = clamp(energyFrac,   0, maxContributionMultiplier)
        let exercisePct = clamp(exerciseFrac, 0, maxContributionMultiplier)

        let ringData = RingData(
            moveRingPct:     stepsPct,    // outer  ring = steps     (red)
            exerciseRingPct: exercisePct, // middle ring = exercise  (green)
            standRingPct:    energyPct,   // inner  ring = energy    (blue)
            stepsPct:        stepsPct,
            activeEnergyPct: energyPct,
            syncSource:      .iphone,
            exerciseMinutes: exerciseMinutes,
            exerciseGoal:    exerciseGoal,
            steps:           steps,
            stepsGoal:       stepsGoal,
            activeEnergy:    activeEnergy,
            activeEnergyGoal: activeEnergyGoal
        )
        return (points, ringData)
    }

    // MARK: - Private helpers

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
