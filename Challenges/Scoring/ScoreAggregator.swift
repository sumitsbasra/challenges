import Foundation

/// Rolls up an array of DailyScore records into leaderboard-ready Participation totals.
enum ScoreAggregator {

    /// Mutates `participations` in-place: sums totalPoints and assigns rank.
    static func aggregate(_ participations: inout [Participation]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in participations.indices {
            // Deduplicate by calendar day, keeping the highest-scoring record per day.
            // Duplicate CloudKit records can accumulate from save retries (e.g. the
            // .allKeys save policy used in saveParticipation), which would otherwise
            // inflate point totals. Also excludes future-dated scores from UTC skew.
            var best: [Date: Double] = [:]
            for score in participations[i].dailyScores {
                let day = cal.startOfDay(for: score.date)
                guard day <= today else { continue }
                best[day] = max(best[day] ?? 0, score.points)
            }
            participations[i].totalPoints = best.values.reduce(0, +)
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
