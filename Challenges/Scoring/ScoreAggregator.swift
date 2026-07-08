import Foundation

/// Rolls up an array of DailyScore records into leaderboard-ready Participation totals.
enum ScoreAggregator {

    /// Mutates `participations` in-place: sums totalPoints and assigns rank.
    static func aggregate(_ participations: inout [Participation], localCalendar: Calendar = .current) {
        // Score dates are noon UTC encoding the scorer's local day, so bucket in UTC.
        // Allow one day beyond the viewer's local today: participants in timezones
        // ahead of the viewer legitimately have scores for the viewer's "tomorrow".
        let localToday = DailyScore.day(of: DailyScore.noonUTC(for: Date(), localCalendar: localCalendar))
        let maxDay = localToday.addingTimeInterval(86_400)
        for i in participations.indices {
            // Deduplicate by calendar day, keeping the highest-scoring record per day.
            // Duplicate CloudKit records can accumulate from save retries (e.g. the
            // .allKeys save policy used in saveParticipation), which would otherwise
            // inflate point totals. Also excludes bogus far-future-dated scores.
            var best: [Date: Double] = [:]
            for score in participations[i].dailyScores {
                let day = DailyScore.day(of: score.date)
                guard day <= maxDay else { continue }
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
