import SwiftUI

struct NewChallengeView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm = NewChallengeViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Title field
                        FitnessFormCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Challenge Name", systemImage: "trophy.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.moveRing)
                                TextField("e.g. Summer Ring Crush", text: Bindable(vm).title)
                                    .font(.body)
                                    .textInputAutocapitalization(.words)
                            }
                        }

                        // Date section
                        FitnessFormCard {
                            VStack(spacing: 12) {
                                DatePicker("Start Date",
                                           selection: Bindable(vm).startDate,
                                           in: tomorrow...,
                                           displayedComponents: .date)
                                    .foregroundStyle(.primary)

                                Divider()

                                HStack {
                                    Label("End Date", systemImage: "flag.checkered")
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(vm.endDate.formatted(.dateTime.month(.abbreviated).day().year()))
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                    Text("All challenges run for exactly 7 days.")
                                        .font(.caption)
                                }
                                .foregroundStyle(.tertiary)
                            }
                        }

                        // Max participants
                        FitnessFormCard {
                            Stepper {
                                HStack {
                                    Label("Max Participants", systemImage: "person.2.fill")
                                        .font(.body)
                                    Spacer()
                                    Text("\(vm.maxParticipants)")
                                        .font(.body.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.exerciseRing)
                                        .frame(width: 30, alignment: .trailing)
                                }
                            } onIncrement: {
                                if vm.maxParticipants < 20 { vm.maxParticipants += 1 }
                            } onDecrement: {
                                if vm.maxParticipants > 2 { vm.maxParticipants -= 1 }
                            }
                        }

                        // Invite code preview
                        FitnessFormCard {
                            VStack(spacing: 14) {
                                InviteCodeView(code: vm.inviteCode)
                                Text("Share this code after creating your challenge.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if let error = vm.error {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView().tint(.moveRing)
                    } else {
                        Button("Create") {
                            Task {
                                guard let userID = session.userID else { return }
                                await vm.create(creatorID: userID)
                                if vm.createdChallenge != nil { dismiss() }
                            }
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(vm.canCreate ? .moveRing : .tertiary)
                        .disabled(!vm.canCreate)
                    }
                }
            }
        }
    }

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    }
}

