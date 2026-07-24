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

    /// True when the permission dialog has been shown but no activity data is readable —
    /// the only way to infer a denied READ permission, which Apple deliberately hides
    /// (`authorizationStatus(for:)` reflects write access only, and
    /// `statusForAuthorizationRequest` returns `.unnecessary` for "asked", whether the
    /// user allowed or denied). Set by `checkDataReadable()`.
    @Published var dataUnreadable = false

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

    /// Infers whether activity data is actually readable, since iOS never reports a
    /// denied READ permission. Looks for ANY steps or active-energy sample in the last
    /// 7 days: a carried iPhone always generates some, so a completely empty result
    /// means the app is almost certainly blocked (or the user has genuinely never
    /// carried the device, which produces the same zero score either way — both are
    /// worth surfacing rather than silently showing 0 points).
    ///
    /// Only meaningful once the dialog has been shown; skipped otherwise so a
    /// pre-onboarding user isn't warned about a permission they haven't been asked for.
    func checkDataReadable() async {
        guard HKHealthStore.isHealthDataAvailable(), authorizationStatus == .authorized else {
            dataUnreadable = false
            return
        }
        let end = Date()
        let start = end.addingTimeInterval(-7 * 24 * 3600)
        async let steps = anySamples(HKQuantityType(.stepCount), from: start, to: end)
        async let energy = anySamples(HKQuantityType(.activeEnergyBurned), from: start, to: end)
        let (hasSteps, hasEnergy) = await (steps, energy)
        dataUnreadable = !hasSteps && !hasEnergy
    }

    /// True if at least one sample of `type` exists in the range. A HealthKit error
    /// returns false (treated as unreadable) — the same outcome a denial produces.
    private func anySamples(_ type: HKSampleType, from start: Date, to end: Date) async -> Bool {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: !(samples ?? []).isEmpty)
            }
            store.execute(query)
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
