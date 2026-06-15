import AppIntents

/// "Create a challenge in Challenges" — opens the New Challenge sheet.
struct CreateChallengeIntent: AppIntent {
    static var title: LocalizedStringResource = "Create a Challenge"
    static var description = IntentDescription("Start creating a new fitness challenge.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .openNewChallenge, object: nil)
        return .result()
    }
}
