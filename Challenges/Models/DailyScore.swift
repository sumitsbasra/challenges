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
    static func noonUTC(for date: Date, localCalendar: Calendar = .current) -> Date {
        // Extract the LOCAL calendar day to avoid off-by-one errors when local time
        // is late enough that the UTC date has already rolled over to the next day.
        let components = localCalendar.dateComponents([.year, .month, .day], from: date)
        var noonComponents = components
        noonComponents.hour = 12
        noonComponents.minute = 0
        noonComponents.second = 0
        guard let noon = utcCalendar.date(from: noonComponents) else {
            Logger.app.error("DailyScore.noonUTC failed to compute noon for \(date, privacy: .public) — falling back to UTC start of day + 12h")
            return utcCalendar.startOfDay(for: date).addingTimeInterval(12 * 3600)
        }
        return noon
    }

    /// The `date` field is always noon UTC, so day identity must be derived with a UTC
    /// calendar. Using the viewer's local calendar shifts the day for timezones at
    /// UTC+12 and beyond (noon UTC is already the next local day there).
    static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return cal
    }()

    /// UTC-day bucket for grouping/deduplicating scores.
    static func day(of scoreDate: Date) -> Date {
        utcCalendar.startOfDay(for: scoreDate)
    }

    /// True when this score is for the given local calendar day.
    func isFor(localDay: Date, localCalendar: Calendar = .current) -> Bool {
        Self.utcCalendar.isDate(date, inSameDayAs: Self.noonUTC(for: localDay, localCalendar: localCalendar))
    }

    /// True when this score is for the viewer's current local calendar day.
    var isForToday: Bool {
        isFor(localDay: Date())
    }

    /// Start of the encoded calendar day in the viewer's local calendar — for plotting
    /// alongside local dates (chart axes, day cells).
    func localDayStart(in localCalendar: Calendar = .current) -> Date {
        let comps = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        return localCalendar.date(from: comps) ?? date
    }
}
