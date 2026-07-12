import Foundation

/// A lightweight emoji reaction sent from one participant to another within a challenge.
struct Reaction: Identifiable, Codable, Hashable {
    /// Deterministic: "\(fromParticipationID)_\(toParticipationID)_\(yyyy-MM-dd)".
    /// One reaction per sender→recipient per day — re-sending the same day updates
    /// the emoji instead of creating a new record, which doubles as spam control.
    let id: String
    let challengeID: String
    /// Denormalised so a push can render "…in <title>" without fetching the challenge.
    let challengeTitle: String
    let fromUserID: String
    /// Denormalised sender name — same rationale as Participation.displayName.
    let fromName: String
    let toUserID: String
    let toParticipationID: String
    var emoji: String
    var createdAt: Date

    /// Quick-send reactions, always visible (iMessage-tapback style).
    static let allowedEmojis = ["🔥", "👏", "😤"]

    /// The expanded picker behind "More reactions". Together with the quick three
    /// this makes 30 — an even 5 rows in the picker's 6-column grid.
    static let extendedEmojis = [
        "💪", "🏃", "🚴", "⚡️", "🎯", "🏆",
        "🥇", "👑", "🙌", "👀", "😮", "😂",
        "🤯", "🫡", "🥵", "😅", "😴", "🏋️",
        "🐢", "🦥", "🛋️", "❤️", "💀", "🚀",
        "🤝", "🥶", "🍕",
    ]

    /// True when the emoji is one the app can send.
    static func isValid(_ emoji: String) -> Bool {
        allowedEmojis.contains(emoji) || extendedEmojis.contains(emoji)
    }

    static func makeID(fromParticipationID: String, toParticipationID: String,
                       date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return "\(fromParticipationID)_\(toParticipationID)_\(formatter.string(from: date))"
    }

    /// True when this reaction was sent on the viewer's current local calendar day.
    var isFromToday: Bool {
        Calendar.current.isDateInToday(createdAt)
    }
}
