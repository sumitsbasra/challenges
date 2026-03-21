import AppIntents

/// "What's my rank in [Challenge]?"
///
/// On iOS 16–18.0 Siri matches the registered phrases exactly.
/// On iOS 18.1+ with Apple Intelligence, Siri understands natural paraphrases
/// semantically — the same conformance powers both.
///
/// Returns a spoken result in-place without opening the app.
struct CheckMyRankIntent: AppIntent {
    static var title: LocalizedStringResource = "Check My Rank"
    static var description = IntentDescription(
        "See your current leaderboard rank and points in a challenge."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Challenge")
    var challenge: ChallengeEntity

    @MainActor
    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        guard let userID = UserSession.shared.userID else {
            return .result(
                value: "Not signed in",
                dialog: "Sign in to the Challenges app to check your rank."
            )
        }

        // Fetch participations and scores for the requested challenge.
        var participations = try await CloudKitManager.shared.fetchParticipations(
            challengeID: challenge.id
        )
        let scores = try await CloudKitManager.shared.fetchDailyScores(
            challengeID: challenge.id
        )

        // Map scores onto participations, then rank them.
        for i in participations.indices {
            participations[i].dailyScores = scores.filter {
                $0.participationID == participations[i].id
            }
        }
        let ranked = ScoreAggregator.ranked(participations)

        guard let mine = ranked.first(where: { $0.user.id == userID }) else {
            return .result(
                value: "Not participating",
                dialog: "You aren't participating in \(challenge.title)."
            )
        }

        let pts = String(format: "%.0f", mine.totalPoints)
        let total = ranked.count
        let dialog = "You're ranked #\(mine.rank) out of \(total) in \(challenge.title) with \(pts) points."
        return .result(
            value: "#\(mine.rank)",
            dialog: IntentDialog(stringLiteral: dialog)
        )
    }
}
