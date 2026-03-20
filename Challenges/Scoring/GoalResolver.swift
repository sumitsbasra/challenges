import Foundation
import HealthKit

/// Resolves the user's activity goals from HealthKit (Watch path) or from
/// stored preferences (non-Watch path).
@MainActor
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
    /// available HKActivitySummary. Falls back to 400 kcal if unavailable.
    func moveGoal() async -> Double {
        await withCheckedContinuation { continuation in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: calendar.dateComponents([.year, .month, .day], from: today),
                                              end: calendar.dateComponents([.year, .month, .day], from: tomorrow))

            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                let goal = summaries?.first?.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()) ?? 400
                continuation.resume(returning: max(goal, 1))
            }
            healthStore.execute(query)
        }
    }
}
