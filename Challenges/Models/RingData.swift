import Foundation

enum SyncSource: String, Codable {
    case watch, iphone, manual
}

/// Raw ring/metric percentages as fractions of the user's goal (1.0 = 100%).
/// Values can exceed 1.0 (up to 2.0 max for bonus points).
struct RingData: Codable {
    // Watch path
    var moveRingPct: Double      // 0.0–2.0+
    var exerciseRingPct: Double  // 0.0–2.0+
    var standRingPct: Double     // 0.0–2.0+; 0 for non-Watch users

    // Non-Watch path
    var stepsPct: Double         // 0.0–2.0+; 0 for Watch users
    var activeEnergyPct: Double  // 0.0–2.0+

    var syncSource: SyncSource
}
