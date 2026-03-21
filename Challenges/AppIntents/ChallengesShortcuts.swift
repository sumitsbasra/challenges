import AppIntents

/// Registers App Shortcuts so they appear automatically in the Shortcuts app
/// and Siri suggestions — no user setup required.
///
/// On iOS 18.1+ with Apple Intelligence, Siri understands natural paraphrases
/// of these phrases semantically, so users don't need to memorize exact wording.
///
/// The `\(.applicationName)` token is required by Apple in at least one phrase
/// variant per shortcut for disambiguation between apps.
struct ChallengesShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        AppShortcut(
            intent: CheckMyRankIntent(),
            phrases: [
                "Check my rank in \(.applicationName)",
                "What's my rank in \(\.$challenge) in \(.applicationName)",
                "How am I doing in \(\.$challenge) in \(.applicationName)"
            ],
            shortTitle: "Check My Rank",
            systemImageName: "trophy.fill"
        )

        AppShortcut(
            intent: ShowChallengeIntent(),
            phrases: [
                "Show \(\.$challenge) in \(.applicationName)",
                "Open \(\.$challenge) challenge in \(.applicationName)"
            ],
            shortTitle: "Show Challenge",
            systemImageName: "figure.run"
        )

        AppShortcut(
            intent: CreateChallengeIntent(),
            phrases: [
                "Create a challenge in \(.applicationName)",
                "New challenge in \(.applicationName)"
            ],
            shortTitle: "Create Challenge",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: GetActiveChallengesIntent(),
            phrases: [
                "Show my active challenges in \(.applicationName)"
            ],
            shortTitle: "Active Challenges",
            systemImageName: "list.bullet"
        )
    }
}
