import SwiftUI

struct NewChallengeView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm = NewChallengeViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Challenge Details") {
                    TextField("Challenge name", text: Bindable(vm).title)
                        .textInputAutocapitalization(.words)

                    DatePicker("Start Date",
                               selection: Bindable(vm).startDate,
                               in: tomorrow...,
                               displayedComponents: .date)

                    HStack {
                        Text("End Date")
                        Spacer()
                        Text(vm.endDate, style: .date)
                            .foregroundStyle(Color.secondaryText)
                    }
                }

                Section("Participants") {
                    Stepper("Max \(vm.maxParticipants) participants",
                            value: Bindable(vm).maxParticipants,
                            in: 2...20)
                }

                Section("Invite Code") {
                    VStack(alignment: .center, spacing: 12) {
                        InviteCodeView(code: vm.inviteCode)
                        Text("Share this code with friends so they can join your challenge.")
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                            .multilineTextAlignment(.center)

                        ShareLink(
                            item: URL(string: "challenges://join/\(vm.inviteCode)")!,
                            message: Text("Join my fitness challenge! Use code \(vm.inviteCode)")
                        ) {
                            Label("Share Invite", systemImage: "square.and.arrow.up")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if let error = vm.error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task {
                                guard let userID = session.userID else { return }
                                await vm.create(creatorID: userID)
                                if vm.createdChallenge != nil { dismiss() }
                            }
                        }
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
