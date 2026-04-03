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
