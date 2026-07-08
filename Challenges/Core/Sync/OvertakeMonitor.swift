import Foundation
import UserNotifications
import OSLog

/// Detects rank drops between syncs and fires a "you've been passed" notification.
///
/// `SyncCoordinator` calls `evaluate` with fresh standings after every sync (foreground,
/// background refresh, HealthKit delivery, silent push), so the comparison happens
/// wherever the rank actually changes — no extra polling.
enum OvertakeMonitor {

    struct Overtake: Equatable {
        let passerName: String
        let pointsBehind: Double
        let newRank: Int
    }

    /// Pure comparison: returns the overtake if the user's rank got worse since the
    /// previously recorded rank. The named passer is whoever is directly ahead now.
    static func detect(previousRank: Int?, standings: [Participation], userID: String) -> Overtake? {
        guard
            let mine = standings.first(where: { $0.user.id == userID }),
            let previousRank,
            mine.rank > previousRank,
            let passer = standings.first(where: { $0.rank == mine.rank - 1 })
        else { return nil }
        return Overtake(
            passerName: passer.user.displayName,
            pointsBehind: max(0, passer.totalPoints - mine.totalPoints),
            newRank: mine.rank
        )
    }

    /// Compares fresh standings against the stored rank, fires a local notification on
    /// a drop, and records the new rank for the next comparison.
    static func evaluate(challenge: Challenge, standings: [Participation], userID: String) async {
        guard challenge.status == .active else { return }
        let defaults = UserDefaults.standard
        let rankKey = "overtake.lastRank.\(challenge.id)"

        let previousRank = defaults.object(forKey: rankKey) as? Int
        let overtake = detect(previousRank: previousRank, standings: standings, userID: userID)

        if let mine = standings.first(where: { $0.user.id == userID }) {
            defaults.set(mine.rank, forKey: rankKey)
        }

        guard let overtake else { return }
        await notify(overtake, challenge: challenge)
    }

    // MARK: - Notification

    private static func notify(_ overtake: Overtake, challenge: Challenge) async {
        guard UserDefaults.standard.object(forKey: "notif.overtaken") as? Bool ?? true else { return }

        // Ranks can ping-pong between 15-minute background syncs; one alert per
        // challenge per cooldown window keeps the rivalry fun instead of noisy.
        let throttleKey = "overtake.lastNotified.\(challenge.id)"
        let cooldown: TimeInterval = 3 * 3600
        if let last = UserDefaults.standard.object(forKey: throttleKey) as? Date,
           Date().timeIntervalSince(last) < cooldown { return }

        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "You've been passed 🏃"
        content.body  = body(for: overtake, challengeTitle: challenge.title)
        content.sound = .default
        content.userInfo = ["challengeID": challenge.id]

        // Fixed identifier per challenge: a newer overtake replaces an undelivered one.
        let request = UNNotificationRequest(
            identifier: "ch-overtake-\(challenge.id)",
            content: content,
            trigger: nil  // deliver immediately
        )
        do {
            try await center.add(request)
            UserDefaults.standard.set(Date(), forKey: throttleKey)
        } catch {
            Logger.sync.error("OvertakeMonitor failed to add notification for \(challenge.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    static func body(for overtake: Overtake, challengeTitle: String) -> String {
        let points = Int(overtake.pointsBehind.rounded())
        return "\(overtake.passerName) just passed you in \(challengeTitle). You're \(points) points behind. Go get them!"
    }
}
