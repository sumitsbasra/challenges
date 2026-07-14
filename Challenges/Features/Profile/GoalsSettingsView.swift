import SwiftUI

/// Lets non-Watch users customize their daily step and active energy goals.
struct GoalsSettingsView: View {
    @State private var goalResolver = GoalResolver()
    @State private var stepsGoal: Double = 10_000
    @State private var energyGoal: Double = 500
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily Steps Goal")
                            .font(.subheadline.weight(.medium))
                        HStack {
                            Slider(value: $stepsGoal, in: 2_000...20_000, step: 500)
                            Text("\(Int(stepsGoal))")
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily Active Energy Goal (kcal)")
                            .font(.subheadline.weight(.medium))
                        HStack {
                            Slider(value: $energyGoal, in: 100...1500, step: 50)
                            Text("\(Int(energyGoal))")
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("iPhone User Goals")
                } footer: {
                    Text("These goals are used to calculate your points when you don't have an Apple Watch. 100% of your goal = 300 pts/day. 200% = 600 pts/day (max).")
                }
            }
            .navigationTitle("My Goals")
            .navigationBarTitleDisplayMode(.inline)
            .softTopScrollEdge()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        goalResolver.stepsGoal = stepsGoal
                        goalResolver.activeEnergyGoal = energyGoal
                        dismiss()
                    }
                }
            }
            .onAppear {
                stepsGoal = goalResolver.stepsGoal
                energyGoal = goalResolver.activeEnergyGoal
            }
        }
    }
}
