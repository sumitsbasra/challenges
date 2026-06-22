import Foundation

/// A single recorded workout, denormalized for cross-device display.
///
/// HealthKit data never leaves the device that recorded it, so each participant's
/// device builds these summaries from its own `HKWorkout`s and syncs them to CloudKit.
/// The recording device resolves `name`/`systemImage` (it has HealthKit), so other
/// participants can render the workout without any HealthKit access of their own.
struct WorkoutSummary: Identifiable, Codable, Hashable {
    /// Deterministic: "{participationID}_{workoutUUID}" so re-syncs upsert, never duplicate.
    let id: String
    let participationID: String
    let challengeID: String
    let name: String          // e.g. "Running", "Strength Training"
    let systemImage: String   // SF Symbol, e.g. "figure.run"
    let date: Date            // workout start
    let duration: Double      // seconds
    let activeEnergy: Double  // kcal (0 if unavailable)
    let distance: Double      // meters (0 if N/A)

    static func makeID(participationID: String, workoutUUID: String) -> String {
        "\(participationID)_\(workoutUUID)"
    }

    /// "32 min", "1h 05m".
    var durationText: String {
        let totalMinutes = Int((duration / 60).rounded())
        if totalMinutes < 60 { return "\(totalMinutes) min" }
        return "\(totalMinutes / 60)h \(String(format: "%02d", totalMinutes % 60))m"
    }
}
