import Foundation

enum ChallengeStatus: String, Codable, CaseIterable {
    case pending, active, completed
}

struct Challenge: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var creatorID: String
    var startDate: Date
    var endDate: Date
    var status: ChallengeStatus
    var inviteCode: String      // 6-char alphanumeric, e.g. "FX4K9R"
    var createdAt: Date

    var isOwned: Bool = false   // transient, set by the app after fetch
    var participants: [Participation] = []  // transient, populated after fetch

    static func == (lhs: Challenge, rhs: Challenge) -> Bool {
        lhs.id        == rhs.id        &&
        lhs.title     == rhs.title     &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate   == rhs.endDate   &&
        lhs.status    == rhs.status
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(startDate)
        hasher.combine(endDate)
        hasher.combine(status)
    }
}

// MARK: - Countdown formatting

extension Challenge {
    /// Whole calendar days from `now` until the challenge starts (clamped at 0).
    func daysUntilStart(now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: startDate)).day ?? 0)
    }

    /// "Starts today" / "Starts tomorrow" / "Starts in N days" for a pending challenge.
    /// Single source of truth so the home row badge and the detail header never drift.
    func startCountdownText(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch daysUntilStart(now: now, calendar: calendar) {
        case 0:  return "Starts today"
        case 1:  return "Starts tomorrow"
        case let days: return "Starts in \(days) days"
        }
    }

    /// Full status-aware countdown used by the detail header.
    func countdownText(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch status {
        case .pending:
            return startCountdownText(now: now, calendar: calendar)
        case .active:
            if calendar.isDateInToday(endDate)    { return "Ends today" }
            if calendar.isDateInTomorrow(endDate) { return "Ends tomorrow" }
            return "Ongoing"
        case .completed:
            return "Completed"
        }
    }
}
