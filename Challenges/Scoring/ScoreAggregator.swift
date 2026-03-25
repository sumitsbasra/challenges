import Foundation

/// Rolls up an array of DailyScore records into leaderboard-ready Participation totals.
enum ScoreAggregator {

    /// Mutates `participations` in-place: sums totalPoints and assigns rank.
    static func aggregate(_ participations: inout [Participation]) {
        for i in participations.indices {
            participations[i].totalPoints = participations[i].dailyScores
                .reduce(0) { $0 + $1.points }
        }
        participations.sort {
            if $0.totalPoints != $1.totalPoints { return $0.totalPoints > $1.totalPoints }
            if $0.joinedAt != $1.joinedAt { return $0.joinedAt < $1.joinedAt }
            return $0.user.id < $1.user.id
        }
        for i in participations.indices {
            participations[i].rank = i + 1
        }
    }

    /// Returns a new sorted array without mutating the input.
    static func ranked(_ participations: [Participation]) -> [Participation] {
        var copy = participations
        aggregate(&copy)
        return copy
    }

    /// Returns the rank of the given user in the provided (already-aggregated) list.
    static func rank(of userID: String, in participations: [Participation]) -> Int? {
        participations.first(where: { $0.user.id == userID })?.rank
    }
}
