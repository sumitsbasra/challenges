import Foundation
import UserNotifications

/// Schedules and cancels local notifications for all challenge lifecycle events.
///
/// Call `reschedule(for:)` any time the challenge list changes (on load, join, create).
/// Call `remove(challengeID:)` when the user deletes or leaves a specific challenge.
/// Call `rescheduleFromPrefs(challenges:)` when the user toggles notification prefs in Settings.
enum NotificationScheduler {

    // MARK: - Public API

    /// Rebuilds all pending challenge notifications from scratch.
    /// Safe to call repeatedly — removes stale entries before adding fresh ones.
    static func reschedule(for challenges: [Challenge]) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let prefs = NotificationPrefs()
        var requests: [UNNotificationRequest] = []

        for challenge in challenges {
            switch challenge.status {
            case .pending:
                startingRequest(for: challenge, prefs: prefs).map { requests.append($0) }
            case .active:
                endingRequest(for: challenge, prefs: prefs).map  { requests.append($0) }
                finalRequest(for: challenge, prefs: prefs).map   { requests.append($0) }
                requests += dailyRequests(for: challenge, prefs: prefs)
            case .completed:
                break
            }
        }

        // Atomically replace all existing challenge notifications
        await removeAllChallenge(center: center)
        for req in requests { try? await center.add(req) }
    }

    /// Removes all pending notifications for a single challenge.
    /// Call after the user deletes or leaves a challenge.
    static func remove(challengeID: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .filter { containsChallenge($0.identifier, id: challengeID) }
            .map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    // MARK: - Per-type builders

    private static func startingRequest(for challenge: Challenge, prefs: NotificationPrefs) -> UNNotificationRequest? {
        guard prefs.challengeStarting,
              let fireDate = atHour(9, onDayBefore: challenge.startDate) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Challenge starts tomorrow 🔥"
        content.body  = "\(challenge.title) kicks off tomorrow. Get ready to close your rings!"
        content.sound = .default
        content.userInfo = ["challengeID": challenge.id]

        return request(id: "ch-starting-\(challenge.id)", content: content, fireDate: fireDate)
    }

    private static func endingRequest(for challenge: Challenge, prefs: NotificationPrefs) -> UNNotificationRequest? {
        guard prefs.challengeEnding,
              let fireDate = atHour(9, onDayBefore: challenge.endDate) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Last day to compete 💪"
        content.body  = "\(challenge.title) ends tomorrow. Push hard and close those rings!"
        content.sound = .default
        content.userInfo = ["challengeID": challenge.id]

        return request(id: "ch-ending-\(challenge.id)", content: content, fireDate: fireDate)
    }

    private static func finalRequest(for challenge: Challenge, prefs: NotificationPrefs) -> UNNotificationRequest? {
        guard prefs.finalStandings else { return nil }
        // Fire 1 hour after the challenge ends
        let fireDate = challenge.endDate.addingTimeInterval(3600)
        guard fireDate > Date() else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Challenge complete 🏆"
        content.body  = "\(challenge.title) has ended. See how you finished!"
        content.sound = .default
        content.userInfo = ["challengeID": challenge.id]

        return request(id: "ch-final-\(challenge.id)", content: content, fireDate: fireDate)
    }

    private static func dailyRequests(for challenge: Challenge, prefs: NotificationPrefs) -> [UNNotificationRequest] {
        guard prefs.dailyUpdate else { return [] }

        let cal = Calendar.current
        let now = Date()
        // Start from tomorrow — no point notifying about standings on challenge day 0
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return [] }
        let endDay = cal.startOfDay(for: challenge.endDate)

        var requests: [UNNotificationRequest] = []
        var day = tomorrow

        while day <= endDay && requests.count < 7 { // respect the 64-notification system cap
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = 9
            if let fireDate = cal.date(from: comps), fireDate > now {
                let dayTag = isoDay(day)
                let content = UNMutableNotificationContent()
                content.title = "How are you ranking? 📊"
                content.body  = "Check your standings in \(challenge.title)."
                content.sound = .default
                content.userInfo = ["challengeID": challenge.id]
                requests.append(request(
                    id: "ch-daily-\(challenge.id)-\(dayTag)",
                    content: content,
                    fireDate: fireDate
                ))
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return requests
    }

    // MARK: - Helpers

    private static func request(id: String, content: UNMutableNotificationContent, fireDate: Date) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// Returns 9am (or `hour`) on the calendar day before `date`, or nil if that moment is in the past.
    private static func atHour(_ hour: Int, onDayBefore date: Date) -> Date? {
        let cal = Calendar.current
        guard let dayBefore = cal.date(byAdding: .day, value: -1, to: date) else { return nil }
        var comps = cal.dateComponents([.year, .month, .day], from: dayBefore)
        comps.hour = hour
        guard let result = cal.date(from: comps), result > Date() else { return nil }
        return result
    }

    private static func removeAllChallenge(center: UNUserNotificationCenter) async {
        let pending = await center.pendingNotificationRequests()
        let prefixes = ["ch-starting-", "ch-ending-", "ch-final-", "ch-daily-"]
        let toRemove = pending
            .filter { req in prefixes.contains { req.identifier.hasPrefix($0) } }
            .map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    private static func containsChallenge(_ identifier: String, id: String) -> Bool {
        identifier.hasPrefix("ch-starting-\(id)") ||
        identifier.hasPrefix("ch-ending-\(id)")   ||
        identifier.hasPrefix("ch-final-\(id)")    ||
        identifier.hasPrefix("ch-daily-\(id)-")
    }

    private static func isoDay(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }
}

// MARK: - Preferences snapshot (reads UserDefaults once)

private struct NotificationPrefs {
    let challengeStarting: Bool
    let dailyUpdate: Bool
    let challengeEnding: Bool
    let finalStandings: Bool

    init() {
        func pref(_ key: String) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? true
        }
        challengeStarting = pref("notif.challengeStarting")
        dailyUpdate       = pref("notif.dailyUpdate")
        challengeEnding   = pref("notif.challengeEnding")
        finalStandings    = pref("notif.finalStandings")
    }
}
