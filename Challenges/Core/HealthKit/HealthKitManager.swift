import Foundation
import HealthKit

/// Manages HealthKit authorization and provides a single shared `HKHealthStore`.
@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    let store = HKHealthStore()

    @Published var authorizationStatus: AuthorizationStatus = .unknown

    enum AuthorizationStatus {
        case unknown, authorized, partiallyAuthorized, denied
    }

    // MARK: - Permission types

    static var readTypes: Set<HKObjectType> {
        [
            // Universal (Watch + non-Watch)
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.appleExerciseTime),

            // Watch-specific (gracefully absent on non-Watch)
            HKCategoryType(.appleStandHour),
            HKQuantityType(.appleStandTime),

            // Activity summary (ring goals + completion)
            HKObjectType.activitySummaryType(),

            // Workout data (contributes to active energy)
            HKObjectType.workoutType(),

            // Heart rate — used for Watch detection heuristic
            HKQuantityType(.heartRate),
        ]
    }

    // MARK: - Authorization

    /// Requests all necessary HealthKit read permissions.
    /// Must be called from a user-facing interaction (button tap).
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationStatus = .denied
            return
        }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
        updateAuthorizationStatus()
    }

    /// Refreshes the published authorization status based on current HealthKit state.
    func updateAuthorizationStatus() {
        let coreTypes: [HKObjectType] = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
        ]

        let allAuthorized = coreTypes.allSatisfy {
            store.authorizationStatus(for: $0) == .sharingAuthorized
        }
        let anyAuthorized = coreTypes.contains {
            store.authorizationStatus(for: $0) == .sharingAuthorized
        }

        if allAuthorized {
            authorizationStatus = .authorized
        } else if anyAuthorized {
            authorizationStatus = .partiallyAuthorized
        } else {
            authorizationStatus = .denied
        }
    }
}
