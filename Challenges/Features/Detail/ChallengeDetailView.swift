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
            LazyVStack(alignment: .leading, spacing: 16) {
                // Header card: countdown + status
                headerCard

                // Leaderboard
                GroupBox("Leaderboard") {
                    if vm.participations.isEmpty && vm.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if vm.rankedParticipations.isEmpty {
                        Text("No participants yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        LeaderboardView(
                            participations: vm.rankedParticipations,
                            currentUserID: session.userID ?? ""
                        )
                    }
                }
                .padding(.horizontal)

                // My Progress
                if let me = vm.currentUserParticipation {
                    GroupBox("My Progress") {
                        MyProgressView(participation: me)
                    }
                    .padding(.horizontal)

                    GroupBox("Daily Breakdown") {
                        DailyBreakdownView(participation: me, challengeStartDate: challenge.startDate)
                    }
                    .padding(.horizontal)
                }

                // Invite code (for creator, pending challenges only)
                if challenge.status == .pending,
                   let myID = session.userID,
                   challenge.creatorID == myID {
                    GroupBox("Invite Friends") {
                        VStack(spacing: 12) {
                            InviteCodeView(code: challenge.inviteCode)
                            ShareLink(
                                item: URL(string: "challenges://join/\(challenge.inviteCode)")!,
                                message: Text("Join my fitness challenge! Code: \(challenge.inviteCode)")
                            ) {
                                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.large)
        .background(Color.appBackground)
        .task { await vm.load() }
        .refreshable { await vm.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dailyScoreDidUpdate)) { _ in
            Task { await vm.handleScoreUpdate() }
        }
    }

    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.countdownText)
                    .font(.countdownTimer())
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())

                Text("\(challenge.startDate.formatted(date: .abbreviated, time: .omitted)) – \(challenge.endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Text("\(vm.participations.filter { $0.status == .active }.count)/\(challenge.maxParticipants)")
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
            Image(systemName: "person.2")
                .foregroundStyle(Color.secondaryText)
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var statusColor: Color {
        switch challenge.status {
        case .active:    return .exerciseRing
        case .pending:   return .stepsColor
        case .completed: return .secondaryText
        }
    }
}
