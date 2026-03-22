import Foundation

/// Persists participation + score data per challenge so the detail view
/// can render instantly from cache while a background refresh runs.
struct ParticipationCache {

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    private static func key(for challengeID: String) -> String {
        "participation_cache_\(challengeID)"
    }

    static func load(challengeID: String) -> [Participation]? {
        guard
            let data = UserDefaults.standard.data(forKey: key(for: challengeID)),
            let parts = try? decoder.decode([Participation].self, from: data)
        else { return nil }
        return parts
    }

    static func save(_ participations: [Participation], challengeID: String) {
        if let data = try? encoder.encode(participations) {
            UserDefaults.standard.set(data, forKey: key(for: challengeID))
        }
    }
}
