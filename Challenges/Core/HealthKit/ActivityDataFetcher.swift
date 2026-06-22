import Foundation
import HealthKit

/// Fetches daily activity data from HealthKit for a given date range.
actor ActivityDataFetcher {

    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    // MARK: - Activity summary (Watch path)

    /// Returns HKActivitySummary objects for each calendar day in the range.
    func activitySummaries(from startDate: Date, to endDate: Date) async -> [Date: HKActivitySummary] {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            var start = calendar.dateComponents([.year, .month, .day], from: startDate)
            start.calendar = calendar

            // HKActivitySummaryQuery treats the end DateComponents as EXCLUSIVE,
            // so bump it forward one day to make the requested endDate inclusive.
            // e.g. querying "today → today" would otherwise return nothing.
            let endPlusOne = calendar.date(byAdding: .day, value: 1, to:
                calendar.startOfDay(for: endDate)) ?? endDate
            var end = calendar.dateComponents([.year, .month, .day], from: endPlusOne)
            end.calendar = calendar
            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: start, end: end)

            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                var result: [Date: HKActivitySummary] = [:]
                for summary in summaries ?? [] {
                    if let date = calendar.date(from: summary.dateComponents(for: calendar)) {
                        result[calendar.startOfDay(for: date)] = summary
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    /// Returns the HKActivitySummary for a single calendar day, or nil if unavailable.
    func activitySummary(on date: Date) async -> HKActivitySummary? {
        let summaries = await activitySummaries(from: date, to: date)
        return summaries[Calendar.current.startOfDay(for: date)]
    }

    // MARK: - Steps

    /// Returns step count for the given calendar day, or nil if the query errored.
    func steps(on date: Date) async -> Double? {
        await querySum(
            type: HKQuantityType(.stepCount),
            unit: .count(),
            on: date
        )
    }

    // MARK: - Distance

    /// Returns walking + running distance (meters) for the given calendar day, or nil on error.
    func distanceMeters(on date: Date) async -> Double? {
        await querySum(
            type: HKQuantityType(.distanceWalkingRunning),
            unit: .meter(),
            on: date
        )
    }

    // MARK: - Stand hours (Watch path)

    /// Returns the number of stand-hours credited for the given calendar day, or nil on error.
    /// Counts HKCategoryType(.appleStandHour) samples where value == .stood.
    func standHours(on date: Date) async -> Double? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end   = calendar.date(byAdding: .day, value: 1, to: start) ?? Date(timeInterval: 86400, since: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.appleStandHour),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                // Distinguish a real read failure (nil) from a genuine zero-stand day.
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let count = (samples as? [HKCategorySample])?
                    .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
                    .count ?? 0
                continuation.resume(returning: Double(count))
            }
            store.execute(query)
        }
    }

    // MARK: - Active energy (non-Watch path)

    /// Returns active energy burned (kcal) for the given calendar day, or nil on error.
    func activeEnergy(on date: Date) async -> Double? {
        await querySum(
            type: HKQuantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            on: date
        )
    }

    // MARK: - Exercise minutes (fallback)

    /// Returns exercise minutes for the given calendar day, or nil on error.
    func exerciseMinutes(on date: Date) async -> Double? {
        await querySum(
            type: HKQuantityType(.appleExerciseTime),
            unit: .minute(),
            on: date
        )
    }

    // MARK: - Workouts

    /// Returns all workouts that start within the given range, oldest first.
    func workouts(from start: Date, to end: Date) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    /// Builds a cross-device summary from a HealthKit workout. Resolves the display
    /// name/icon here (where HealthKit is available) so other participants don't need it.
    static func summary(from workout: HKWorkout, participationID: String, challengeID: String) -> WorkoutSummary {
        let (name, icon) = workoutDisplay(workout.workoutActivityType)
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        let distance = (workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()
            ?? workout.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity())?
            .doubleValue(for: .meter()) ?? 0
        return WorkoutSummary(
            id: WorkoutSummary.makeID(participationID: participationID,
                                      workoutUUID: workout.uuid.uuidString),
            participationID: participationID,
            challengeID: challengeID,
            name: name,
            systemImage: icon,
            date: workout.startDate,
            duration: workout.duration,
            activeEnergy: energy,
            distance: distance
        )
    }

    /// Maps an activity type to a display name and SF Symbol; falls back to a generic workout.
    static func workoutDisplay(_ type: HKWorkoutActivityType) -> (name: String, icon: String) {
        switch type {
        case .running:                    return ("Running", "figure.run")
        case .walking:                    return ("Walking", "figure.walk")
        case .cycling:                    return ("Cycling", "figure.outdoor.cycle")
        case .hiking:                     return ("Hiking", "figure.hiking")
        case .swimming:                   return ("Swimming", "figure.pool.swim")
        case .traditionalStrengthTraining,
             .functionalStrengthTraining: return ("Strength", "figure.strengthtraining.traditional")
        case .highIntensityIntervalTraining: return ("HIIT", "figure.highintensity.intervaltraining")
        case .yoga:                       return ("Yoga", "figure.yoga")
        case .pilates:                    return ("Pilates", "figure.pilates")
        case .coreTraining:               return ("Core", "figure.core.training")
        case .elliptical:                 return ("Elliptical", "figure.elliptical")
        case .rowing:                     return ("Rowing", "figure.rower")
        case .cardioDance, .socialDance:  return ("Dance", "figure.dance")
        case .stairClimbing, .stairs:     return ("Stairs", "figure.stair.stepper")
        case .tennis:                     return ("Tennis", "figure.tennis")
        case .basketball:                 return ("Basketball", "figure.basketball")
        case .soccer:                     return ("Soccer", "figure.indoor.soccer")
        default:                          return ("Workout", "figure.mixed.cardio")
        }
    }

    // MARK: - Private helpers

    /// Returns the cumulative sum for `type`, or nil if HealthKit returned an error.
    /// A nil result means "couldn't read" — callers must not persist it as a real zero.
    private func querySum(type: HKQuantityType, unit: HKUnit, on date: Date) async -> Double? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end   = calendar.date(byAdding: .day, value: 1, to: start) ?? Date(timeInterval: 86400, since: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
