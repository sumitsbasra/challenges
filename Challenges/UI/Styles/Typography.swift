import SwiftUI

// MARK: - Typography System
//
// All fonts use SF Pro (system default) to match Apple Fitness precisely.
// Rounded design is used for numeric displays to feel more friendly.

extension Font {

    // MARK: - Ring metric values (matches Apple Fitness Activity card)
    static func metricValue() -> Font {
        .system(size: 24, weight: .bold, design: .rounded)
    }
    static func metricGoal() -> Font {
        .system(size: 18, weight: .semibold, design: .rounded)
    }
    static func metricUnit() -> Font {
        .system(size: 10, weight: .bold)
    }

    // MARK: - Leaderboard
    static func leaderboardPoints() -> Font {
        .system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
    }
    static func leaderboardSecondary() -> Font {
        .system(size: 11, weight: .regular)
    }

    // MARK: - Section headers (Apple Fitness style — 17pt semibold)
    static func fitnessHeader() -> Font {
        .system(size: 17, weight: .semibold)
    }

    // MARK: - Hero display (large points, rank)
    static func heroPoints() -> Font {
        .system(size: 52, weight: .black, design: .rounded)
    }

    // MARK: - Countdown / monospaced metadata
    static func countdownTimer() -> Font {
        .system(size: 13, weight: .semibold, design: .monospaced)
    }

    // MARK: - Compatibility aliases used across existing views
    static func pointsLarge()  -> Font { .system(size: 48, weight: .bold, design: .rounded) }
    static func pointsMedium() -> Font { .system(size: 22, weight: .bold, design: .rounded) }
    static func pointsSmall()  -> Font { .system(size: 16, weight: .semibold, design: .rounded) }
    static func rankBadge()    -> Font { .system(size: 13, weight: .bold, design: .rounded) }
    static func sectionHeader() -> Font { fitnessHeader() }
}
