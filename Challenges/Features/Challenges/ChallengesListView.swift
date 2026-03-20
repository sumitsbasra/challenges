import SwiftUI

struct ChallengesListView: View {
    @Environment(UserSession.self) private var session
    @State private var vm = ChallengesListViewModel()
    @State private var showNewChallenge = false
    @State private var showJoinChallenge = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.challenges.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.filteredChallenges.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Challenges")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Challenge") { showNewChallenge = true }
                        Button("Join with Code") { showJoinChallenge = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("Filter", selection: Bindable(vm).filter) {
                    ForEach(ChallengesListViewModel.Filter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showNewChallenge) {
            NewChallengeView()
        }
        .sheet(isPresented: $showJoinChallenge) {
            JoinChallengeView()
        }
        .task {
            guard let userID = session.userID else { return }
            await vm.load(userID: userID)
        }
        .refreshable {
            guard let userID = session.userID else { return }
            await vm.load(userID: userID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .participationDidChange)) { _ in
            Task {
                guard let userID = session.userID else { return }
                await vm.load(userID: userID)
            }
        }
    }

    private var list: some View {
        List(vm.filteredChallenges) { challenge in
            NavigationLink(value: challenge) {
                ChallengeRowView(challenge: challenge, currentUserID: session.userID ?? "")
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: Challenge.self) { challenge in
            ChallengeDetailView(challenge: challenge)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "trophy",
            title: "No \(vm.filter.rawValue.lowercased()) challenges",
            message: vm.filter == .active
                ? "Start one with friends and see who closes their rings the most."
                : "Your past and upcoming challenges will appear here.",
            actionTitle: vm.filter == .active ? "Get Started" : nil,
            action: vm.filter == .active ? { showNewChallenge = true } : nil
        )
    }
}

private struct ChallengeRowView: View {
    let challenge: Challenge
    let currentUserID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(challenge.title)
                    .font(.headline)
                Spacer()
                StatusBadge(status: challenge.status)
            }
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                Text(challenge.startDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                Text("–")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                Text(challenge.endDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatusBadge: View {
    let status: ChallengeStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption.weight(.medium))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var badgeColor: Color {
        switch status {
        case .active:    return .exerciseRing
        case .pending:   return .stepsColor
        case .completed: return .secondaryText
        }
    }
}
