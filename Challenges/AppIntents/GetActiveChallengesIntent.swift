import AppIntents

/// "Show my active challenges" — returns a list of active ChallengeEntities.
/// Useful for Shortcuts automation (e.g. "If I have an active challenge, remind me at 7pm").
struct GetActiveChallengesIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Active Challenges"
    static var description = IntentDescription(
        "Returns your currently active fitness challenges."
    )
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some ReturnsValue<[ChallengeEntity]> & ProvidesDialog {
        guard let userID = UserSession.shared.userID else {
            return .result(
                value: [],
                dialog: "Sign in to the Challenges app to see your active challenges."
            )
        }

        let all = try await CloudKitManager.shared.fetchChallenges(forUserID: userID)
        let active = all
            .filter { $0.status == .active }
            .map { ChallengeEntity(challenge: $0) }

        let dialog: String
        switch active.count {
        case 0:  dialog = "You have no active challenges right now."
        case 1:  dialog = "You have 1 active challenge: \(active[0].title)."
        default: dialog = "You have \(active.count) active challenges."
        }

        return .result(value: active, dialog: IntentDialog(stringLiteral: dialog))
    }
}
