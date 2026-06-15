import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct RankEntry: TimelineEntry {
    let date: Date
    let state: WidgetState?
}

// MARK: - Timeline Provider

struct RankTimelineProvider: TimelineProvider {
    typealias Entry = RankEntry

    func placeholder(in context: Context) -> RankEntry {
        RankEntry(date: .now, state: WidgetState(
            challengeTitle: "Summer Ring Crush",
            challengeID: "",
            rank: 2,
            totalPoints: 1840,
            daysRemaining: 3,
            participantCount: 5,
            updatedAt: .now
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (RankEntry) -> Void) {
        completion(RankEntry(date: .now, state: WidgetDataStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RankEntry>) -> Void) {
        let state = WidgetDataStore.read()
        let entry = RankEntry(date: .now, state: state)
        // Refresh every hour; the main app also triggers a reload via WidgetCenter after each sync.
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }


}

// MARK: - Widget

struct ChallengesRankWidget: Widget {
    let kind = "ChallengesRankWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RankTimelineProvider()) { entry in
            RankWidgetView(entry: entry)
                .containerBackground(Color.black, for: .widget)
        }
        .configurationDisplayName("My Rank")
        .description("Your current leaderboard rank and points.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Shared App Group reader (widget-side)

/// Reads WidgetState from the shared App Group UserDefaults.
/// The main app writes this via WidgetDataWriter after each sync.
private enum WidgetDataStore {
    private static let suiteName = "group.studio.ssb.challenges"
    private static let key = "widgetState"

    static func read() -> WidgetState? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(WidgetState.self, from: data)
        else { return nil }
        return state
    }
}

// MARK: - WidgetState (mirrored from main app)

/// Must stay in sync with WidgetDataWriter.WidgetState in the main app target.
struct WidgetState: Codable {
    var challengeTitle: String
    var challengeID: String
    var rank: Int
    var totalPoints: Double
    var daysRemaining: Int
    var participantCount: Int
    var updatedAt: Date
}
