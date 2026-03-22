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


