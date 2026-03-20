import SwiftUI

@Observable
final class JoinChallengeViewModel {

    var code: String = "" {
        didSet {
            let upper = code.uppercased().filter { $0.isLetter || $0.isNumber }
            if upper != code { code = upper }
            if code.count == 6 { Task { await lookupChallenge() } }
            if code.count < 6 { previewChallenge = nil; error = nil }
        }
    }
    var previewChallenge: Challenge? = nil
    var isLooking: Bool = false
    var isJoining: Bool = false
    var error: String? = nil
    var joined: Bool = false

    private let ck = CloudKitManager.shared

    @MainActor
    func lookupChallenge() async {
        guard code.count == 6 else { return }
        isLooking = true
        error = nil
        defer { isLooking = false }

        do {
            previewChallenge = try await ck.fetchChallenge(inviteCode: code)
        } catch let ckError as CloudKitError {
            error = ckError.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func joinChallenge(userID: String, hasWatch: Bool) async {
        guard let challenge = previewChallenge else { return }
        isJoining = true
        error = nil
        defer { isJoining = false }

        let participation = Participation(
            id: UUID().uuidString,
            challengeID: challenge.id,
            user: AppUser(id: userID, displayName: "", appleUserID: "", hasAppleWatch: hasWatch),
            joinedAt: Date(),
            status: .active,
            hasAppleWatch: hasWatch
        )

        do {
            try await ck.saveParticipation(participation)
            joined = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct JoinChallengeView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm = JoinChallengeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter Invite Code")
                    .font(.title2.bold())
                    .padding(.top, 32)

                // 6-character code entry
                TextField("FX4K9R", text: Bindable(vm).code)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: vm.code) { _, new in
                        if new.count > 6 { vm.code = String(new.prefix(6)) }
                    }
                    .padding()
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)

                if vm.isLooking {
                    ProgressView("Finding challenge…")
                } else if let challenge = vm.previewChallenge {
                    ChallengePreviewCard(challenge: challenge)
                        .padding(.horizontal)

                    if let error = vm.error {
                        Text(error).foregroundStyle(.red).font(.caption)
                    }

                    Button {
                        Task {
                            guard let userID = session.userID else { return }
                            let hasWatch = session.currentUser?.hasAppleWatch ?? false
                            await vm.joinChallenge(userID: userID, hasWatch: hasWatch)
                            if vm.joined { dismiss() }
                        }
                    } label: {
                        Group {
                            if vm.isJoining { ProgressView() }
                            else { Text("Join Challenge") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                } else if let error = vm.error {
                    Text(error).foregroundStyle(.red).font(.subheadline)
                }

                Spacer()
            }
            .navigationTitle("Join")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct ChallengePreviewCard: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(challenge.title)
                .font(.headline)
            HStack {
                Image(systemName: "calendar")
                Text("\(challenge.startDate.formatted(date: .abbreviated, time: .omitted)) – \(challenge.endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            HStack {
                Image(systemName: "person.2")
                Text("\(challenge.participants.count) / \(challenge.maxParticipants) participants")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
