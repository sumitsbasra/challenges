import Foundation

enum ParticipationStatus: String, Codable {
    case invited, active, declined
}

struct Participation: Identifiable, Codable {
    let id: String
    let challengeID: String
    var user: AppUser
    var joinedAt: Date
    var status: ParticipationStatus
    /// Snapshotted at join time — scoring mode never changes mid-competition.
    var hasAppleWatch: Bool

    // Computed / transient — populated by ScoreAggregator after fetching DailyScores.
    var dailyScores: [DailyScore] = []
    var totalPoints: Double = 0
    var rank: Int = 0
}
