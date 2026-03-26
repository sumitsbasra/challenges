import Foundation

enum SyncSource: String, Codable {
    case watch, iphone, manual
}

/// Raw ring/metric data — percentages (for scoring) plus actual values and goals (for display).
/// Percentages can exceed 1.0 up to 2.0 max for bonus points.
/// Actual values default to 0 for backward-compatible decoding of older records.
struct RingData: Codable {
    // ── Watch path ────────────────────────────────────────────────
    var moveRingPct: Double      // 0.0–2.0+
    var exerciseRingPct: Double  // 0.0–2.0+
    var standRingPct: Double     // 0.0–2.0+; 0 for non-Watch users

    // ── Non-Watch path ────────────────────────────────────────────
    var stepsPct: Double         // 0.0–2.0+; 0 for Watch users
    var activeEnergyPct: Double  // 0.0–2.0+

    var syncSource: SyncSource

    // ── Actual values (stored so the card can show "actual / goal") ─
    var moveCalories:    Double = 0
    var moveGoal:        Double = 700
    var exerciseMinutes: Double = 0
    var exerciseGoal:    Double = 30
    var standHours:      Double = 0
    var standGoal:       Double = 12
    var steps:            Double = 0
    var stepsGoal:        Double = 10_000
    var activeEnergy:     Double = 0
    var activeEnergyGoal: Double = 500

    // Shown for all users regardless of Watch status
    var totalSteps:     Double = 0   // step count for the day
    var distanceMeters: Double = 0   // walking+running distance in meters
}
