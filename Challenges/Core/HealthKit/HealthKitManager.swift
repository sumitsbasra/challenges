import Foundation
import HealthKit
import OSLog

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

    /// Sample types we watch for background delivery. iOS wakes the app when any of
    /// these gets new data (e.g. when the Watch syncs activity), letting us re-sync
    /// scores without the user opening the app. Must be `HKSampleType`s — the activity
    /// summary type can't back an `HKObserverQuery`, so we observe the underlying
    /// quantity/category samples instead.
    static var backgroundDeliveryTypes: [HKSampleType] {
        [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.distanceWalkingRunning),
            HKCategoryType(.appleStandHour),
        ]
    }

    private var backgroundDeliveryStarted = false

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

    // MARK: - Background delivery

    /// Registers an `HKObserverQuery` + background delivery for each scored sample type.
    ///
    /// When new activity data lands in HealthKit, iOS launches the app in the background
    /// and fires the observer's update handler, which runs the normal sync. This keeps
    /// scores reasonably fresh without the user opening the app. Background delivery for
    /// cumulative quantities is throttled by iOS to roughly hourly — this complements,
    /// rather than replaces, the foreground sync and the BGAppRefreshTask backstop.
    ///
    /// Safe to call more than once; observers are only registered on the first call.
    func startBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable(), !backgroundDeliveryStarted else { return }
        backgroundDeliveryStarted = true

        for type in Self.backgroundDeliveryTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                // Always call completionHandler so HealthKit knows we're done and keeps
                // delivering; skipping it can suspend future background launches.
                guard error == nil else {
                    completionHandler()
                    return
                }
                Task {
                    await SyncCoordinator.shared.syncCurrentChallenges()
                    completionHandler()
                }
            }
            store.execute(query)

            store.enableBackgroundDelivery(for: type, frequency: .hourly) { success, error in
                if let error {
                    Logger.health.error("enableBackgroundDelivery failed for \(type, privacy: .public): \(error.localizedDescription, privacy: .public)")
                } else {
                    Logger.health.notice("background delivery enabled for \(type, privacy: .public): \(success, privacy: .public)")
                }
            }
        }
    }
}
