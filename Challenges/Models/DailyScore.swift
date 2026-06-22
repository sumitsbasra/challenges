import Foundation
import OSLog

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
        formatter.timeZone = TimeZone.current  // local timezone so ID matches the user's calendar day
        return "\(participationID)_\(formatter.string(from: date))"
    }

    /// Returns noon UTC for the given local calendar date, ensuring stable day identity
    /// anchored to the user's local day rather than the UTC day.
    static func noonUTC(for date: Date) -> Date {
        // Extract the LOCAL calendar day to avoid off-by-one errors when local time
        // is late enough that the UTC date has already rolled over to the next day.
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        var noonComponents = components
        noonComponents.hour = 12
        noonComponents.minute = 0
        noonComponents.second = 0
        guard let noon = cal.date(from: noonComponents) else {
            Logger.app.error("DailyScore.noonUTC failed to compute noon for \(date, privacy: .public) — falling back to input date")
            return date
        }
        return noon
    }
}
