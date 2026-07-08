import SwiftUI

// MARK: - Data Model

struct TodayItem: Identifiable, Codable {
    let id: String                  // challenge.id
    let challenge: Challenge
    let rank: Int
    let participantCount: Int
    let todayPoints: Double
    let totalPoints: Double

    var daysRemaining: Int {
        challenge.daysRemaining()
    }

    var daysRemainingText: String {
        let cal = Calendar.current
        if cal.isDateInToday(challenge.endDate)    { return "Ends today" }
        if cal.isDateInTomorrow(challenge.endDate) { return "Ends tomorrow" }
        return "Ongoing"
    }
}
