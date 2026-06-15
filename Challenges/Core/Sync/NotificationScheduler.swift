import Foundation
import UserNotifications

/// Schedules and cancels local notifications for all challenge lifecycle events.
///
/// Call `reschedule(for:)` any time the challenge list changes (on load, join, create).
/// Call `remove(challengeID:)` when the user deletes or leaves a specific challenge.
enum NotificationScheduler {

    // MARK: - Public API

    /// Rebuilds all pending challenge notifications from scratch.
    /// Safe to call repeatedly — removes stale entries before adding fresh ones.
    ///
    /// Notification cadence:
    ///   • Day before a challenge starts  → per-challenge "starts tomorrow" reminder.
    ///   • First day of a challenge       → per-challenge "challenge begins today" push.
    ///   • Last day of a challenge        → per-challenge "final day" push.
    ///   • 1 h after a challenge ends     → per-challenge "see your results" push.
    ///   • Every other active-challenge day → ONE generic daily notification regardless
    ///                                        of how many challenges the user is in.
    static func reschedule(for challenges: [Challenge]) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let prefs = NotificationPrefs()
        var requests: [UNNotificationRequest] = []

        // ── 1. Per-challenge lifecycle notifications ──────────────────────────
        for challenge in challenges {
            switch challenge.status {
            case .pending:
                startingRequest(for: challenge, prefs: prefs).map { requests.append($0) }
            case .active:
                firstDayRequest(for: challenge, prefs: prefs).map  { requests.append($0) }
                lastDayRequest(for: challenge, prefs: prefs).map   { requests.append($0) }
                finalRequest(for: challenge, prefs: prefs).map     { requests.append($0) }
            case .completed:
                break
            }
        }

        // ── 2. One generic daily notification (replaces per-challenge dailies) ─
        // No matter how many active challenges the user is in, they receive exactly
        // one reminder per day — eliminating notification spam for multi-challenge users.
        if prefs.dailyUpdate {
            let active = challenges.filter { $0.status == .active }
            if !active.isEmpty {
                // Budget: iOS caps pending notifications at 64.
                // Lifecycle slots per non-completed challenge: up to 4
                // (starting, first-day, last-day, final).
                let lifecycleBudget = challenges.filter { $0.status != .completed }.count * 4
                let dailyBudget = max(0, 64 - lifecycleBudget)

                requests += genericDailyRequests(for: active, prefs: prefs, limit: dailyBudget)
            }
        }

        // Atomically replace all existing challenge notifications.
        await removeAllChallenge(center: center)
        for req in requests {
            do {
                try await center.add(req)
            } catch {
                #if DEBUG
                print("[NotificationScheduler] Failed to add \(req.identifier): \(error)")
                #endif
            }
        }
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

    // MARK: - Per-challenge lifecycle builders

    /// 5 PM the day before the challenge starts — "starts tomorrow".
    private static func startingRequest(for challenge: Challenge, prefs: NotificationPrefs) -> UNNotificationRequest? {
        guard prefs.challengeStarting,
              let fireDate = atHour(17, onDayBefore: challenge.startDate) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Challenge starts \(noHyphen("tomorrow")) 🔥"
        content.body  = startingBodies[stableIndex(challenge.id, count: startingBodies.count)](challenge)
        content.sound = .default
        content.userInfo = ["challengeID": challenge.id]

        return request(id: "ch-starting-\(challenge.id)", content: content, fireDate: fireDate)
    }

    /// 9 AM on the first day of the challenge — "starts today".
    private static func firstDayRequest(for challenge: Challenge, prefs: NotificationPrefs) -> UNNotificationRequest? {
        guard prefs.challengeStarting,
              let fireDate = atHour(9, on: challenge.startDate),
              fireDate > Date() else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "\(challenge.title) starts today! 🏁"
        content.body  = "Day 1 is here. Get moving and build an early lead!"
        content.sound = .default
        content.userInfo = ["challengeID": challenge.id]

        return request(id: "ch-firstday-\(challenge.id)", content: content, fireDate: fireDate)
    }

    /// 9 AM on the last day of the challenge — "final day, give it everything".
    private static func lastDayRequest(for challenge: Challenge, prefs: NotificationPrefs) -> UNNotificationRequest? {
        guard prefs.challengeEnding,
              let fireDate = atHour(9, on: challenge.endDate),
              fireDate > Date() else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Final day, leave it all on the field 💪"
        content.body  = "\(challenge.title) ends today. Close those rings!"
        content.sound = .default
        content.userInfo = ["challengeID": challenge.id]

        return request(id: "ch-lastday-\(challenge.id)", content: content, fireDate: fireDate)
    }

    /// 9 AM the day after the challenge ends — "see your final results".
    private static func finalRequest(for challenge: Challenge, prefs: NotificationPrefs) -> UNNotificationRequest? {
        guard prefs.finalStandings,
              let fireDate = atHour(9, onDayAfter: challenge.endDate),
              fireDate > Date() else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Challenge complete 🏆"
        content.body  = completeBodies[stableIndex(challenge.id, count: completeBodies.count)](challenge)
        content.sound = .default
        content.userInfo = ["challengeID": challenge.id]

        return request(id: "ch-final-\(challenge.id)", content: content, fireDate: fireDate)
    }

    // MARK: - Generic daily notifications

    /// Builds one notification per calendar day that any active challenge covers.
    /// The message is generic when multiple challenges are active, or names the
    /// challenge when the user is in only one.
    private static func genericDailyRequests(
        for activeChallenges: [Challenge],
        prefs: NotificationPrefs,
        limit: Int
    ) -> [UNNotificationRequest] {
        guard prefs.dailyUpdate else { return [] }

        let cal = Calendar.current
        let now = Date()
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return [] }

        // Furthest end date across all active challenges.
        guard let latestEnd = activeChallenges.map({ $0.endDate }).max() else { return [] }
        let endDay = cal.startOfDay(for: latestEnd)

        var requests: [UNNotificationRequest] = []
        var day = tomorrow

        while day <= endDay && requests.count < limit {
            // Which challenges are still running on this day?
            let running = activeChallenges.filter { challenge in
                let start = cal.startOfDay(for: challenge.startDate)
                let end   = cal.startOfDay(for: challenge.endDate)
                return day >= start && day <= end
            }

            if !running.isEmpty {
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = 9
                if let fireDate = cal.date(from: comps), fireDate > now {
                    let content = UNMutableNotificationContent()
                    content.sound = .default
                    // Rotate the copy by day-of-year so consecutive days differ.
                    let dayOfYear = cal.ordinality(of: .day, in: .year, for: day) ?? 0
                    if running.count == 1 {
                        let pick = dailySingle[dayOfYear % dailySingle.count]
                        content.title = pick.title
                        content.body  = pick.body(running[0].title)
                    } else {
                        let pick = dailyMultiple[dayOfYear % dailyMultiple.count]
                        content.title = pick.title
                        content.body  = pick.body(running.count)
                    }
                    requests.append(request(
                        id:       "ch-daily-\(isoDay(day))",
                        content:  content,
                        fireDate: fireDate
                    ))
                }
            }

            guard let nextDay = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return requests
    }

    // MARK: - Helpers

    // MARK: - Copy pools

    /// "Challenge starts tomorrow" body variants. Picked per-challenge for variety.
    private static let startingBodies: [(Challenge) -> String] = [
        { "\($0.title) is up next. Get ready to close your rings!" },
        { "Get ready, \($0.title) is about to begin. Time to close some rings!" },
        { "\($0.title) is almost here. Rest up and prep those rings!" },
    ]

    /// "Challenge complete" body variants. Picked per-challenge for variety.
    private static let completeBodies: [(Challenge) -> String] = [
        { "See where you finished in \($0.title)!" },
        { "The results are in for \($0.title). Check your rank!" },
        { "\($0.title) is a wrap. See how you stacked up!" },
    ]

    /// Daily reminder variants when the user is in exactly one challenge (passes its title).
    private static let dailySingle: [(title: String, body: (String) -> String)] = [
        ("Keep pushing! 💪",       { "Check your standings in \($0)." }),
        ("How are your rings? ⭕️", { "A few moves now protects your spot in \($0)." }),
        ("Don't lose ground 🔥",   { "Close your rings to climb in \($0)." }),
        ("Your move 👟",           { "Every ring counts in \($0) today." }),
        ("Climb the board 📈",     { "Log some activity for \($0) and gain ground." }),
    ]

    /// Daily reminder variants when the user is in multiple challenges (passes the count).
    private static let dailyMultiple: [(title: String, body: (Int) -> String)] = [
        ("Stay on top 🏆",                 { "You're in \($0) challenges. Time to close those rings!" }),
        ("Big day ahead 💪",               { "\($0) challenges are counting on you. Get moving!" }),
        ("Keep the momentum 🔥",           { "Rack up points across all \($0) challenges today." }),
        ("Lead the pack 📈",               { _ in "A little activity now lifts you in every challenge." }),
        ("Rings won't close themselves ⭕️", { "You've got \($0) challenges in play. Make them count!" }),
    ]

    /// Deterministic, launch-stable index into a pool of `count` from an arbitrary string
    /// (djb2 hash). Same input always maps to the same slot, so a given challenge keeps
    /// consistent copy across reschedules while different challenges vary.
    private static func stableIndex(_ string: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 5381
        for byte in string.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Int(hash % UInt64(count))
    }

    /// Inserts zero-width word-joiner characters (U+2060) between every letter of `word`
    /// so the system text renderer can't hyphenate it mid-word. On narrow layouts like
    /// the Apple Watch this makes the whole word wrap to the next line ("tomorrow")
    /// instead of splitting it ("to-morrow"). The joiners are invisible and have no
    /// effect where the word already fits (e.g. the iPhone).
    private static func noHyphen(_ word: String) -> String {
        word.map(String.init).joined(separator: "\u{2060}")
    }

    private static func request(id: String, content: UNMutableNotificationContent, fireDate: Date) -> UNNotificationRequest {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// Returns `hour`:00 on the same calendar day as `date`, or nil if already past.
    private static func atHour(_ hour: Int, on date: Date) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        return cal.date(from: comps)
    }

    /// Returns `hour`:00 on the calendar day after `date`, or nil if already past.
    private static func atHour(_ hour: Int, onDayAfter date: Date) -> Date? {
        let cal = Calendar.current
        guard let dayAfter = cal.date(byAdding: .day, value: 1, to: date) else { return nil }
        var comps = cal.dateComponents([.year, .month, .day], from: dayAfter)
        comps.hour = hour
        guard let result = cal.date(from: comps), result > Date() else { return nil }
        return result
    }

    /// Returns `hour`:00 on the calendar day before `date`, or nil if already past.
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
        let prefixes = ["ch-starting-", "ch-firstday-", "ch-lastday-", "ch-final-", "ch-daily-"]
        let toRemove = pending
            .filter { req in prefixes.contains { req.identifier.hasPrefix($0) } }
            .map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    private static func containsChallenge(_ identifier: String, id: String) -> Bool {
        identifier.hasPrefix("ch-starting-\(id)")  ||
        identifier.hasPrefix("ch-firstday-\(id)")  ||
        identifier.hasPrefix("ch-lastday-\(id)")   ||
        identifier.hasPrefix("ch-final-\(id)")
        // Note: generic daily notifications (ch-daily-YYYY-MM-DD) are date-keyed,
        // not challenge-keyed, so they are NOT removed here. They are rebuilt
        // correctly by the next reschedule(for:) call.
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
