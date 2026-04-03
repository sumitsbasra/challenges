import Foundation
import HealthKit

/// Manages HealthKit authorization and provides a single shared `HKHealthStore`.
@MainActor
final class HealthKitManager: ObservableObject {

    static let shared = HealthKitManager()

    let store = HKHealthStore()

    nonisolated init() {}

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
            HKQuantityType(.distanceWalkingRunning),

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
    /// Uses `statusForAuthorizationRequest` because we only request READ access —
    /// `authorizationStatus(for:)` only reflects write (share) authorization, which
    /// will always be `.sharingDenied` when `toShare` is empty.
    func updateAuthorizationStatus() {
        Task {
            guard HKHealthStore.isHealthDataAvailable() else {
                authorizationStatus = .denied
                return
            }
            guard let status = try? await store.statusForAuthorizationRequest(
                toShare: [],
                read: Self.readTypes
            ) else {
                authorizationStatus = .unknown
                return
            }
            // .unnecessary means the user has already been shown the dialog for all
            // requested types (they may have allowed or denied individual items, but
            // HealthKit hides per-type read authorization for user privacy).
            // .shouldRequest means the dialog hasn't been shown yet.
            switch status {
            case .unnecessary:
                authorizationStatus = .authorized
            case .shouldRequest, .unknown:
                authorizationStatus = .unknown
            @unknown default:
                authorizationStatus = .unknown
            }
        }
    }
}
