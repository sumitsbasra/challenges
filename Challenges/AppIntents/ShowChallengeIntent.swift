import AppIntents

/// "Show me [Challenge]" — opens the app to the challenge's detail view.
struct ShowChallengeIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Challenge"
    static var description = IntentDescription("Open a challenge's detail page.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Challenge")
    var challenge: ChallengeEntity

    @MainActor
    func perform() async throws -> some OpensApp {
        NotificationCenter.default.post(
            name: .openChallenge,
            object: nil,
            userInfo: ["challengeID": challenge.id]
        )
        return .result()
    }
}

// MARK: - Shared Notification Names

extension Notification.Name {
    /// Posted when any code path (intent, Siri, Spotlight) wants to navigate to a specific challenge.
    static let openChallenge = Notification.Name("com.challenges.openChallenge")

    /// Posted when the Create Challenge intent fires.
    static let openNewChallenge = Notification.Name("com.challenges.openNewChallenge")
}
