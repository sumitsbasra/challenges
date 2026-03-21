import SwiftUI

struct ChallengeDetailView: View {
    let challenge: Challenge
    @Environment(UserSession.self) private var session
    @State private var vm: ChallengeDetailViewModel

    init(challenge: Challenge) {
        self.challenge = challenge
        _vm = State(initialValue: ChallengeDetailViewModel(challenge: challenge))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 1. Status banner (compact, below nav title)
                statusBanner
                    .padding(.top, 8)

                // 2. Activity hero card (current user's rings)
                if let me = vm.currentUserParticipation, challenge.status == .active {
                    MyProgressView(participation: me)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                }

                // 3. Leaderboard section
                leaderboardSection
                    .padding(.top, 28)

                // 4. Daily breakdown
                if let me = vm.currentUserParticipation {
                    breakdownSection(participation: me)
                        .padding(.top, 28)
                }

                // 5. Invite code — creator only, pending challenges
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
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dailyScoreDidUpdate)) { _ in
            Task { await vm.handleScoreUpdate() }
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(spacing: 0) {
            // Date range
            Label {
                Text("\(challenge.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(challenge.endDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Participants pill
            HStack(spacing: 4) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                Text("\(vm.participations.filter { $0.status == .active }.count)/\(challenge.maxParticipants)")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .padding(.trailing, 12)

            // Countdown pill
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
                                isCurrentUser: p.user.id == session.userID
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

    // MARK: - Daily Breakdown

    private func breakdownSection(participation: Participation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "This Week")
                .padding(.horizontal, 20)

            DailyBreakdownView(
                participation: participation,
                challengeStartDate: challenge.startDate
            )
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "Invite Friends")
                .padding(.horizontal, 20)

            VStack(spacing: 16) {
                InviteCodeView(code: challenge.inviteCode)

                ShareLink(
                    item: URL(string: "challenges://join/\(challenge.inviteCode)")!,
                    message: Text("Join my fitness challenge! Code: \(challenge.inviteCode)")
                ) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Invite")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.moveRing)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(16)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch challenge.status {
        case .active:    return .exerciseRing
        case .pending:   return .stepsColor
        case .completed: return .secondaryText
        }
    }
}

// MARK: - Section Header Component

/// Apple Fitness-style section header: bold white title, optional "See All" action.
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
                    .foregroundStyle(.accent)
            }
        }
    }
}
