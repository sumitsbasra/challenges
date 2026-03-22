import SwiftUI
import Intents

struct ChallengeDetailView: View {
    let challenge: Challenge
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ChallengeDetailViewModel
    @State private var showDeleteConfirm = false
    @State private var showLeaveConfirm  = false

    init(challenge: Challenge) {
        self.challenge = challenge
        _vm = State(initialValue: ChallengeDetailViewModel(challenge: challenge))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 1. Status banner
                statusBanner
                    .padding(.top, 8)

                // 2. Activity hero card (current user's rings)
                if let me = vm.currentUserParticipation, challenge.status == .active {
                    MyProgressView(participation: me)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                }

                // 3. Leaderboard
                leaderboardSection
                    .padding(.top, 28)

                // 4. Invite code — creator only, pending challenges
                if challenge.status == .pending,
                   challenge.creatorID == (session.userID ?? "") {
                    inviteSection
                        .padding(.top, 28)
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Share button
                if challenge.status == .pending,
                   challenge.creatorID == (session.userID ?? "") {
                    ShareLink(
                        item: URL(string: "challenges://join/\(challenge.inviteCode)")!,
                        message: Text("Join my fitness challenge! Code: \(challenge.inviteCode)")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                // … menu
                Menu {
                    if challenge.creatorID == (session.userID ?? "") {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Challenge", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label("Leave Challenge", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Challenge?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await vm.deleteChallenge()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the challenge for everyone.")
        }
        .alert("Leave Challenge?", isPresented: $showLeaveConfirm) {
            Button("Leave", role: .destructive) {
                Task {
                    guard let userID = session.userID else { return }
                    try? await vm.leaveChallenge(userID: userID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dailyScoreDidUpdate)) { _ in
            Task { await vm.handleScoreUpdate() }
        }
        .userActivity("com.challenges.viewChallenge", isActive: true) { activity in
            activity.title = challenge.title
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.requiredUserInfoKeys = ["challengeID"]
            activity.userInfo = ["challengeID": challenge.id]
            activity.suggestedInvocationPhrase = "Check \(challenge.title)"
        }
        .onChange(of: currentUserRank) { _, rank in
            guard let rank else { return }
            let activity = NSUserActivity(activityType: "com.challenges.checkRank")
            activity.isEligibleForPrediction = true
            activity.userInfo = ["challengeID": challenge.id, "rank": rank]
            activity.suggestedInvocationPhrase = "My rank in \(challenge.title)"
            activity.becomeCurrent()
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(challenge.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(challenge.endDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                let count = vm.participations.filter { $0.status == .active }.count
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                    Text("\(count) participant\(count == 1 ? "" : "s")")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(vm.countdownText)
                .font(.countdownTimer())
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.13))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Leaderboard

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "Leaderboard")
                .padding(.horizontal, 20)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.cardBackground)

                if vm.isLoading && vm.participations.isEmpty {
                    ProgressView()
                        .padding(32)
                } else if vm.rankedParticipations.isEmpty {
                    Text("No participants yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(32)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.rankedParticipations.enumerated()), id: \.element.id) { idx, p in
                            LeaderboardRowView(
                                participation: p,
                                isCurrentUser: p.user.id == session.userID,
                                showRank: challenge.status != .pending
                            )
                            if idx < vm.rankedParticipations.count - 1 {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "Invite Friends")
                .padding(.horizontal, 20)

            InviteCodeView(code: challenge.inviteCode)
                .padding(16)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private var currentUserRank: Int? {
        vm.rankedParticipations.first(where: { $0.user.id == session.userID })?.rank
    }

    private var statusColor: Color {
        switch challenge.status {
        case .active:    return .exerciseRing
        case .pending:   return .stepsColor
        case .completed: return .secondaryText
        }
    }
}

// MARK: - Section Header Component

struct FitnessSectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.fitnessHeader())
                .foregroundStyle(.primary)
            Spacer()
            if let action {
                Button(actionLabel, action: action)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
        }
    }
}
