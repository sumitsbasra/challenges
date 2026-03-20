import Foundation
import HealthKit

/// Fetches daily activity data from HealthKit for a given date range.
actor ActivityDataFetcher {

    private let store: HKHealthStore

    init(store: HKHealthStore = HealthKitManager.shared.store) {
        self.store = store
    }

    // MARK: - Activity summary (Watch path)

    /// Returns HKActivitySummary objects for each calendar day in the range.
    func activitySummaries(from startDate: Date, to endDate: Date) async -> [Date: HKActivitySummary] {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let start = calendar.dateComponents([.year, .month, .day], from: startDate)
            let end   = calendar.dateComponents([.year, .month, .day], from: endDate)
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

    // MARK: - Steps (non-Watch path)

    /// Returns step count for the given calendar day.
    func steps(on date: Date) async -> Double {
        await querySum(
            type: HKQuantityType(.stepCount),
            unit: .count(),
            on: date
        )
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
        let end   = calendar.date(byAdding: .day, value: 1, to: start)!
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
