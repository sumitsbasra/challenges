import Foundation

/// Persists challenge data to UserDefaults so the home screen can render
/// instantly on next launch without waiting for a CloudKit round trip.
struct ChallengeCache {

    private struct Payload: Codable {
        var allChallenges: [Challenge]
        var activeItems: [TodayItem]
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func key(for userID: String) -> String {
        "challenge_cache_\(userID)"
    }

    static func load(userID: String) -> (challenges: [Challenge], activeItems: [TodayItem])? {
        guard
            let data = UserDefaults.standard.data(forKey: key(for: userID)),
            let payload = try? decoder.decode(Payload.self, from: data)
        else { return nil }
        return (payload.allChallenges, payload.activeItems)
    }

    static func save(challenges: [Challenge], activeItems: [TodayItem], userID: String) {
        let payload = Payload(allChallenges: challenges, activeItems: activeItems)
        if let data = try? encoder.encode(payload) {
            UserDefaults.standard.set(data, forKey: key(for: userID))
        }
    }
}
