import Foundation

struct DailyScore: Identifiable, Codable {
    /// Deterministic: "\(participationID)_\(dateString)" where dateString = "yyyy-MM-dd".
    /// This makes every CloudKit write an upsert — never a duplicate record.
    let id: String
    let participationID: String
    let challengeID: String
    let date: Date              // stored as noon UTC to avoid day-boundary issues
    var points: Double          // 0.0–600.0
    var ringData: RingData
    var lastSyncedAt: Date

    static func makeID(participationID: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "\(participationID)_\(formatter.string(from: date))"
    }

    /// Returns noon UTC for the given calendar date, ensuring stable day identity
    /// regardless of viewer timezone.
    static func noonUTC(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let components = cal.dateComponents([.year, .month, .day], from: date)
        var noonComponents = components
        noonComponents.hour = 12
        noonComponents.minute = 0
        noonComponents.second = 0
        guard let noon = cal.date(from: noonComponents) else {
            #if DEBUG
            print("[DailyScore] noonUTC(for:) failed to compute noon for \(date) — falling back to input date")
            #endif
            return date
        }
        return noon
    }
}
