import SwiftUI

// MARK: - Challenges List

struct ChallengesListView: View {
    @Environment(UserSession.self) private var session
    @State private var vm = ChallengesListViewModel()
    @State private var showNewChallenge = false
    @State private var showJoinChallenge = false
    /// Programmatic navigation path — enables intents, Siri, and Spotlight to deep-link
    /// into a challenge detail view without the user tapping.
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if vm.isLoading && vm.challenges.isEmpty {
                    ProgressView()
                        .tint(.exerciseRing)
                } else if vm.filteredChallenges.isEmpty {
                    emptyState
                } else {
                    challengeList
                }

                if let error = vm.error {
                    VStack {
                        Spacer()
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                            .padding(.bottom, 12)
                            .onTapGesture { vm.error = nil }
                    }
                }
            }
            .navigationTitle("Challenges")
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showNewChallenge = true
                        } label: {
                            Label("New Challenge", systemImage: "trophy.fill")
                        }
                        Button {
                            showJoinChallenge = true
                        } label: {
                            Label("Join with Code", systemImage: "qrcode.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.moveRing)
                            .font(.title3)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
            }
            .navigationDestination(for: Challenge.self) { challenge in
                ChallengeDetailView(challenge: challenge)
            }
        }
        .sheet(isPresented: $showNewChallenge) { NewChallengeView() }
        .sheet(isPresented: $showJoinChallenge) { JoinChallengeView() }
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
        // Apply renames directly to the local array — avoids a stale CloudKit round-trip.
        .onReceive(NotificationCenter.default.publisher(for: .challengeDidRename)) { note in
            guard let id    = note.userInfo?["id"]    as? String,
                  let title = note.userInfo?["title"] as? String else { return }
            vm.applyRename(id: id, title: title)
        }
        .onReceive(NotificationCenter.default.publisher(for: .challengeDatesDidChange)) { note in
            guard let id        = note.userInfo?["id"]        as? String,
                  let startDate = note.userInfo?["startDate"] as? Date,
                  let endDate   = note.userInfo?["endDate"]   as? Date else { return }
            vm.applyDateUpdate(id: id, startDate: startDate, endDate: endDate)
        }
        // Deep-link from intents, Siri, and Spotlight tap-throughs.
        .onReceive(NotificationCenter.default.publisher(for: .openChallenge)) { note in
            guard let id = note.userInfo?["challengeID"] as? String,
                  let challenge = vm.challenges.first(where: { $0.id == id }) else { return }
            navigationPath.append(challenge)
        }
        // CreateChallengeIntent: open the New Challenge sheet directly.
        .onReceive(NotificationCenter.default.publisher(for: .openNewChallenge)) { _ in
            showNewChallenge = true
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        Picker("Filter", selection: Bindable(vm).filter) {
            ForEach(ChallengesListViewModel.Filter.allCases, id: \.self) {
                Text($0.rawValue).tag($0)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Challenge List

    private var challengeList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.filteredChallenges) { challenge in
                    NavigationLink(value: challenge) {
                        ChallengeCardView(challenge: challenge)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            systemImage: vm.filter == .active ? "trophy.fill" : "clock",
            title: "No \(vm.filter.rawValue.lowercased()) challenges",
            message: vm.filter == .active
                ? "Start a challenge with friends and see who closes their rings the most."
                : "Your \(vm.filter.rawValue.lowercased()) challenges will appear here.",
            actionTitle: vm.filter == .active ? "Start a Challenge" : nil,
            action: vm.filter == .active ? { showNewChallenge = true } : nil
        )
    }
}

// MARK: - Challenge Card Row

private struct ChallengeCardView: View {
    let challenge: Challenge

    var body: some View {
        HStack(spacing: 0) {
            // Status color bar
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(statusColor)
                .frame(width: 3)
                .padding(.vertical, 16)
                .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top) {
                    Text(challenge.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    StatusPill(status: challenge.status)
                }

                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("\(challenge.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(challenge.endDate.formatted(.dateTime.month(.abbreviated).day(.defaultDigits).year()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(durationLabel)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 16)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var durationLabel: String {
        let days = Calendar.current.dateComponents([.day], from: challenge.startDate, to: challenge.endDate).day ?? 0
        return "\(days) day\(days == 1 ? "" : "s")"
    }

    private var statusColor: Color {
        switch challenge.status {
        case .active:    return .exerciseRing
        case .pending:   return .stepsColor
        case .completed: return Color(.systemGray4)
        }
    }
}

// MARK: - Status Pill

private struct StatusPill: View {
    let status: ChallengeStatus

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .active:    return "Active"
        case .pending:   return "Upcoming"
        case .completed: return "Ended"
        }
    }

    private var color: Color {
        switch status {
        case .active:    return .exerciseRing
        case .pending:   return .stepsColor
        case .completed: return Color(.systemGray4)
        }
    }
}
