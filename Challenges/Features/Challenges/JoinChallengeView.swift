import SwiftUI

// MARK: - View Model

@MainActor
@Observable
final class JoinChallengeViewModel {

    var code: String = "" {
        didSet {
            let upper = code.uppercased().filter { $0.isLetter || $0.isNumber }
            if upper != code { code = upper }
            if code.count > 6 { code = String(code.prefix(6)) }
            if code.count == 6 { Task { await lookupChallenge() } }
            if code.count < 6 { previewChallenge = nil; error = nil; alreadyJoined = false }
        }
    }
    var userID: String? = nil
    var previewChallenge: Challenge? = nil
    var alreadyJoined = false
    var isLooking = false
    var isJoining = false
    var error: String? = nil
    var joined = false

    private let ck = CloudKitManager.shared

    @MainActor
    func lookupChallenge() async {
        guard code.count == 6 else { return }
        isLooking = true
        error = nil
        alreadyJoined = false
        defer { isLooking = false }
        do {
            let challenge = try await ck.fetchChallenge(inviteCode: code)
            // Check membership immediately so the UI can reflect it at preview time
            if let uid = userID {
                let existing = try await ck.fetchParticipations(challengeID: challenge.id)
                if existing.contains(where: { $0.user.id == uid }) {
                    alreadyJoined = true
                }
            }
            previewChallenge = challenge
        } catch let e as CloudKitError {
            error = e.localizedDescription
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

        do {
            // Check if user is already a participant before saving
            let existing = try await ck.fetchParticipations(challengeID: challenge.id)
            if existing.contains(where: { $0.user.id == userID }) {
                error = "You're already in this challenge."
                return
            }

            let participation = Participation(
                id: UUID().uuidString,
                challengeID: challenge.id,
                user: AppUser(id: userID, displayName: "", appleUserID: "", hasAppleWatch: hasWatch),
                joinedAt: Date(),
                status: .active,
                hasAppleWatch: hasWatch
            )
            try await ck.saveParticipation(participation)
            joined = true
        } catch {
            if self.error == nil { self.error = error.localizedDescription }
        }
    }
}

// MARK: - View

struct JoinChallengeView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm = JoinChallengeViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.standRing.opacity(0.12))
                                .frame(width: 72, height: 72)
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 32))
                                .foregroundStyle(.standRing)
                        }
                        .padding(.top, 32)

                        Text("Enter a Code")
                            .font(.title2.bold())
                        Text("Ask the challenge creator for their 6-character invite code.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 32)

                    // Code input
                    FitnessFormCard {
                        TextField("FX4K9R", text: Bindable(vm).code)
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .foregroundStyle(.standRing)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 16)

                    // State: looking / preview / error
                    Group {
                        if vm.isLooking {
                            ProgressView("Finding challenge…")
                                .tint(.standRing)
                                .padding(.top, 28)
                        } else if let challenge = vm.previewChallenge {
                            challengePreview(challenge)
                        } else if let error = vm.error {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.top, 20)
                        }
                    }

                    Spacer()
                }
            }
            .navigationTitle("Join Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func challengePreview(_ challenge: Challenge) -> some View {
        VStack(spacing: 16) {
            FitnessFormCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(challenge.title)
                        .font(.headline)
                    HStack {
                        Image(systemName: "calendar").foregroundStyle(.tertiary)
                        Text("\(challenge.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(challenge.endDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "person.2").foregroundStyle(.tertiary)
                        Text("\(challenge.participants.count) joined")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)

            Button {
                Task {
                    guard let userID = session.userID else { return }
                    let hasWatch = session.currentUser?.hasAppleWatch ?? false
                    await vm.joinChallenge(userID: userID, hasWatch: hasWatch)
                    if vm.joined { dismiss() }
                }
            } label: {
                Group {
                    if vm.isJoining {
                        ProgressView().tint(.white)
                    } else {
                        Text("Join Challenge")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.standRing)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 16)
            .disabled(vm.isJoining)

            if let error = vm.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.top, 20)
    }
}
