import Foundation
import HealthKit

/// Resolves the user's activity goals from HealthKit (Watch path) or from
/// stored preferences (non-Watch path).
final class GoalResolver {

    private let healthStore: HKHealthStore
    private let defaults: UserDefaults

    // Non-Watch goal keys stored in UserDefaults.
    static let stepsGoalKey        = "goalsStepsPerDay"
    static let activeEnergyGoalKey = "goalsActiveEnergyKcal"

    // Apple's fixed defaults for exercise and stand.
    static let defaultExerciseGoalMinutes: Double = 30
    static let defaultStandGoalHours: Double = 12

    init(healthStore: HKHealthStore = .init(), defaults: UserDefaults = .standard) {
        self.healthStore = healthStore
        self.defaults = defaults
    }

    // MARK: - Non-Watch goals (user-configurable)

    var stepsGoal: Double {
        get {
            let stored = defaults.double(forKey: Self.stepsGoalKey)
            return stored > 0 ? stored : 10_000
        }
        set { defaults.set(newValue, forKey: Self.stepsGoalKey) }
    }

    var activeEnergyGoal: Double {
        get {
            let stored = defaults.double(forKey: Self.activeEnergyGoalKey)
            return stored > 0 ? stored : 500
        }
        set { defaults.set(newValue, forKey: Self.activeEnergyGoalKey) }
    }

    // MARK: - Watch goals (from HKActivitySummary)

    /// Returns the user's personalized move (calorie) goal from the most recent
    /// available HKActivitySummary, looking back up to 7 days.
    ///
    /// Today's summary often hasn't synced from Apple Watch yet (Watch pushes
    /// summaries in batches). Looking back a week reliably finds a recent goal
    /// without a network round-trip. Falls back to 400 kcal only if no summary
    /// exists at all (e.g. Watch has never been paired).
    func moveGoal() async -> Double {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? Date(timeInterval: 86400, since: today)

            var startComponents = calendar.dateComponents([.year, .month, .day], from: sevenDaysAgo)
            startComponents.calendar = calendar
            var endComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            endComponents.calendar = calendar
            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComponents,
                                              end: endComponents)

            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                // Use the most recent summary's goal (sort descending by date).
                let sorted = (summaries ?? []).sorted {
                    let d0 = calendar.date(from: $0.dateComponents(for: calendar)) ?? .distantPast
                    let d1 = calendar.date(from: $1.dateComponents(for: calendar)) ?? .distantPast
                    return d0 > d1
                }
                let goal = sorted.first?.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()) ?? 400
                continuation.resume(returning: max(goal, 1))
            }
            self.healthStore.execute(query)
        }
    }
}
