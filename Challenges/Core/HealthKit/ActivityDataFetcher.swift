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

    /// Returns step count for the given calendar day.
    func steps(on date: Date) async -> Double {
        await querySum(
            type: HKQuantityType(.stepCount),
            unit: .count(),
            on: date
        )
    }

    // MARK: - Distance

    /// Returns walking + running distance (meters) for the given calendar day.
    func distanceMeters(on date: Date) async -> Double {
        await querySum(
            type: HKQuantityType(.distanceWalkingRunning),
            unit: .meter(),
            on: date
        )
    }

    // MARK: - Stand hours (Watch path)

    /// Returns the number of stand-hours credited for the given calendar day.
    /// Counts HKCategoryType(.appleStandHour) samples where value == .stood.
    func standHours(on date: Date) async -> Double {
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
            ) { _, samples, _ in
                let count = (samples as? [HKCategorySample])?
                    .filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
                    .count ?? 0
                continuation.resume(returning: Double(count))
            }
            store.execute(query)
        }
    }

    // MARK: - Active energy (non-Watch path)

    /// Returns active energy burned (kcal) for the given calendar day.
    func activeEnergy(on date: Date) async -> Double {
        await querySum(
            type: HKQuantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            on: date
        )
    }

    // MARK: - Exercise minutes (fallback)

    func exerciseMinutes(on date: Date) async -> Double {
        await querySum(
            type: HKQuantityType(.appleExerciseTime),
            unit: .minute(),
            on: date
        )
    }

    // MARK: - Private helpers

    private func querySum(type: HKQuantityType, unit: HKUnit, on date: Date) async -> Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end   = calendar.date(byAdding: .day, value: 1, to: start) ?? Date(timeInterval: 86400, since: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                let value = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
