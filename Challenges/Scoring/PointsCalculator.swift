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

    /// Points each iPhone metric is worth at 100% of goal.
    ///
    /// A Watch scores three rings at 100 points each (300 for a full day). An iPhone
    /// can only measure two of those signals on its own — Apple Exercise Minutes and
    /// Stand Hours are written by the Watch, so an iPhone-only user's exercise value
    /// is structurally zero. Scoring them out of three metrics therefore capped them
    /// near 200 while a Watch user reached 300 for the same effort. Weighting the two
    /// real signals at 150 each restores parity: both goals met = 300, exactly like
    /// closing all three rings.
    static let iPhoneMetricWeight: Double = 150
    /// Points one closed Watch ring is worth.
    static let watchRingWeight: Double = 100

    /// Calculate daily points for a user without an Apple Watch.
    ///
    /// Scored on the two metrics an iPhone measures unaided — steps and active
    /// energy — each weighted so a full day matches a full day of Watch rings.
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
        let stepsFrac  = steps        / max(stepsGoal, 1)
        let energyFrac = activeEnergy / max(activeEnergyGoal, 1)

        // Same principle as the Watch path — sum of goal percentages, capped at 600 —
        // with each of the two metrics worth 1.5 rings so the ceiling matches.
        let points = min(maxPointsPerDay,
                         max(0, stepsFrac + energyFrac) * iPhoneMetricWeight)

        let stepsPct  = clamp(stepsFrac,  0, maxContributionMultiplier)
        let energyPct = clamp(energyFrac, 0, maxContributionMultiplier)

        let ringData = RingData(
            moveRingPct:     stepsPct,   // outer ring = steps  (red)
            exerciseRingPct: 0,          // no Watch, no exercise minutes
            standRingPct:    energyPct,  // inner ring = energy (blue)
            stepsPct:        stepsPct,
            activeEnergyPct: energyPct,
            syncSource:      .iphone,
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
