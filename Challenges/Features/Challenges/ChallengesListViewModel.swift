import Foundation
import Observation

@Observable
final class ChallengesListViewModel {

    var challenges: [Challenge] = []
    var isLoading: Bool = false
    var error: String? = nil

    enum Filter: String, CaseIterable {
        case active = "Active"
        case upcoming = "Upcoming"
        case past = "Past"
    }

    var filter: Filter = .active

    var filteredChallenges: [Challenge] {
        switch filter {
        case .active:   return challenges.filter { $0.status == .active }
        case .upcoming: return challenges.filter { $0.status == .pending }
        case .past:     return challenges.filter { $0.status == .completed }
        }
    }

    private let ck = CloudKitManager.shared

    @MainActor
    func load(userID: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            challenges = try await ck.fetchChallenges(forUserID: userID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
