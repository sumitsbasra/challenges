import Foundation
import WidgetKit

// MARK: - WidgetState

/// Minimal snapshot of the user's top active challenge, written to shared
/// App Group UserDefaults so the widget extension can read it without
/// requiring direct CloudKit or HealthKit access.
struct WidgetState: Codable {
    var challengeTitle: String
    var challengeID: String
    var rank: Int
    var totalPoints: Double
    var daysRemaining: Int
    var participantCount: Int
    var updatedAt: Date
}

// MARK: - WidgetDataWriter

/// Writes WidgetState to the shared App Group UserDefaults and triggers
/// a WidgetKit timeline reload so the widget reflects current data immediately.
enum WidgetDataWriter {

    private static let suiteName = "group.studio.ssb.challenges"
    private static let key = "widgetState"

    static func write(state: WidgetState) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func read() -> WidgetState? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(WidgetState.self, from: data)
        else { return nil }
        return state
    }
}
