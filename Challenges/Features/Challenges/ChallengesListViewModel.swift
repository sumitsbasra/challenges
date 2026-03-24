import Foundation
import Observation

@MainActor
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
            self.error = "Couldn't load challenges. Pull down to try again."
        }
    }

    /// Applies a rename locally so the list reflects the change without a CloudKit re-fetch.
    @MainActor
    func applyRename(id: String, title: String) {
        guard let idx = challenges.firstIndex(where: { $0.id == id }) else { return }
        challenges[idx].title = title
    }

    /// Applies a date change locally so the card updates without a CloudKit re-fetch.
    @MainActor
    func applyDateUpdate(id: String, startDate: Date, endDate: Date) {
        guard let idx = challenges.firstIndex(where: { $0.id == id }) else { return }
        challenges[idx].startDate = startDate
        challenges[idx].endDate   = endDate
    }
}
