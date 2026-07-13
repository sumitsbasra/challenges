import SwiftUI
import HealthKit
import CloudKit

// MARK: - Home View

struct HomeView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm = HomeViewModel()
    @State private var navigationPath: [String] = []
    @State private var showProfile = false
    @State private var showNewChallenge = false
    @State private var newChallengeMode: NewChallengeView.Mode = .create
    @State private var newChallengePrefillCode = ""
    @State private var profilePhoto: UIImage? = nil
    /// Holds a deep-link challenge ID that arrived before challenges finished loading.
    @State private var pendingDeepLinkChallengeID: String? = nil

    private var dateTitle: String {
        Date().formatted(.dateTime.weekday(.wide).month().day())
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottomTrailing) {
                Color.appBackground.ignoresSafeArea()

                scrollContent
                    // Scoped to the home scroll view only. On the NavigationStack the
                    // refresh action leaks into every pushed page and presented sheet
                    // (the environment key is read-only, so they can't opt out).
                    .refreshable {
                        guard let userID = session.userID else { return }
                        await vm.load(userID: userID)
                        let synced = await SyncCoordinator.shared.syncCurrentChallenges()
                        vm.applySyncedScores(synced)
                    }

                // Floating action button
                fab
                    .padding(.trailing, 24)
                    .padding(.bottom, 0)
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    profileButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    moreMenu
                }
            }
            .navigationDestination(for: String.self) { id in
                if let challenge = vm.allChallenges.first(where: { $0.id == id }) {
                    ChallengeDetailView(challenge: challenge)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // The activity card reads HealthKit once via `.task`, which doesn't re-run
            // when the app returns from the background — so the rings/energy would go
            // stale while the day's activity keeps accruing. Refresh on foreground.
            guard newPhase == .active else { return }
            Task { await vm.loadRings() }
        }
        .sheet(isPresented: $showProfile, onDismiss: {
            if let id = session.userID { profilePhoto = AvatarCache.load(userID: id) }
        }) { ProfileView() }
        .sheet(isPresented: $showNewChallenge, onDismiss: {
            Task {
                guard let userID = session.userID else { return }
                await vm.loadChallenges(userID: userID)
            }
        }) {
            NewChallengeView(mode: newChallengeMode, prefillCode: newChallengePrefillCode) { created in
                vm.upcomingChallenges.insert(created, at: 0)
                vm.allChallenges.insert(created, at: 0)
            }
        }
        .task {
            guard let userID = session.userID else { return }
            profilePhoto = AvatarCache.load(userID: userID)
            // Ensure the current user's CloudKit record exists. This is a no-op for
            // existing users but repairs accounts whose initial saveUser failed due to
            // a missing _icloud Create permission on the Users record type.
            if let user = session.currentUser {
                try? await CloudKitManager.shared.saveUser(user)
            }
            await vm.load(userID: userID)
            // Sync today's HealthKit data and immediately patch the home cards so
            // "today pts" reflects the real value rather than stale CloudKit data.
            let synced = await SyncCoordinator.shared.syncCurrentChallenges()
            vm.applySyncedScores(synced)
            BackgroundTaskScheduler.scheduleAppRefresh()
            Task { await NotificationScheduler.reschedule(for: vm.allChallenges) }
            // Pending challenges included so join pushes arrive before the start date.
            let subscribableIDs = vm.allChallenges.filter { $0.status != .completed }.map { $0.id }
            await CloudKitManager.shared.registerSubscriptions(forChallengeIDs: subscribableIDs)
        }
        .tint(.white)
        .onOpenURL { url in
            guard url.scheme == "challenges" else { return }
            if url.host == "challenge",
               let challengeID = url.pathComponents.dropFirst().first {
                NotificationCenter.default.post(
                    name: .openChallenge, object: nil,
                    userInfo: ["challengeID": challengeID]
                )
            } else if url.host == "join",
                      let code = url.pathComponents.dropFirst().first {
                newChallengeMode = .join
                newChallengePrefillCode = code.uppercased()
                showNewChallenge = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .participationDidChange)) { _ in
            Task {
                guard let userID = session.userID else { return }
                await vm.load(userID: userID)
            }
        }
        // Refresh points + rank on the cards whenever scores change in CloudKit
        // (e.g. another participant's push arrives while the home screen is visible).
        .onReceive(NotificationCenter.default.publisher(for: .dailyScoreDidUpdate)) { _ in
            Task {
                guard let userID = session.userID else { return }
                await vm.loadChallenges(userID: userID)
            }
        }
        // Refresh points + rank when the user pops back from a challenge detail view.
        // The detail view syncs HealthKit → CloudKit on open, so the scores in CloudKit
        // are fresh by the time the user navigates back here.
        .onChange(of: navigationPath) { _, newPath in
            guard newPath.isEmpty, let userID = session.userID else { return }
            Task { await vm.loadChallenges(userID: userID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChallenge)) { note in
            guard let id = note.userInfo?["challengeID"] as? String else { return }
            if vm.allChallenges.contains(where: { $0.id == id }) {
                navigationPath.append(id)
            } else {
                // Challenges haven't loaded yet — store and navigate once they arrive.
                pendingDeepLinkChallengeID = id
            }
        }
        .onChange(of: vm.allChallenges) { _, challenges in
            guard let id = pendingDeepLinkChallengeID,
                  challenges.contains(where: { $0.id == id }) else { return }
            pendingDeepLinkChallengeID = nil
            navigationPath.append(id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewChallenge)) { _ in
            showNewChallenge = true
        }
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
    }

    // MARK: - Scroll Content

    @ViewBuilder
    private var scrollContent: some View {
        let hasChallenges = !vm.activeItems.isEmpty || !vm.upcomingChallenges.isEmpty || !vm.completedChallenges.isEmpty
        if !hasChallenges && !vm.isLoadingChallenges {
            // No challenges: fixed layout so empty state centers in remaining space
            VStack(spacing: 0) {
                if let error = vm.error {
                    errorBanner(error)
                }
                activitySection.padding(.top, 8)
                EmptyStateView(
                    systemImage: "trophy.fill",
                    title: "No challenges yet",
                    message: "Invite your friends. Close your rings.\nTop the leaderboard.",
                    actionTitle: "Start a Challenge",
                    action: { showNewChallenge = true }
                )
                .padding(.bottom, 80) // clear the FAB
            }
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(spacing: 24) {
                    if let error = vm.error { errorBanner(error).padding(.horizontal, 16) }
                    activitySection.padding(.top, 8)
                    // Lifetime record — only once the user has finished a challenge.
                    if vm.challengesDone > 0 {
                        ChallengeRecordCard(done: vm.challengesDone, won: vm.challengesWon)
                            .padding(.horizontal, 16)
                    }
                    // Only show the active/upcoming section when it has content —
                    // avoids a floating "Challenges" header with nothing below it
                    // when the user has only completed challenges.
                    if !vm.activeItems.isEmpty || !vm.upcomingChallenges.isEmpty {
                        challengesSection
                    }
                    // Auto-expand completed when there are no active challenges so
                    // the user doesn't need to manually tap "Show Completed".
                    let autoShowCompleted = vm.activeItems.isEmpty && vm.upcomingChallenges.isEmpty
                    if (vm.showCompleted || autoShowCompleted) && !vm.completedChallenges.isEmpty {
                        completedSection
                    }
                }
                .padding(.bottom, 96)
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button { vm.error = nil } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        ringsCard.padding(.horizontal, 16)
    }

    // MARK: - Rings Card

    private var ringsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // "Activity" header lives inside the card
            HStack(spacing: 8) {
                Text("Activity")
                    .font(.fitnessHeader())
                    .foregroundStyle(.primary)
                if vm.isLoadingRings {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            HStack(alignment: .center, spacing: 28) {
                Group {
                    if vm.hasWatch {
                        ThreeRingView(ringData: vm.ringData, size: 132)
                    } else {
                        IPhoneRingView(ringData: vm.ringData, size: 132)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if vm.hasWatch {
                        HomeMetricRow(label: "Move",     current: vm.activeEnergy,    goal: vm.moveGoal,     unit: "cal", color: .moveRing)
                        HomeMetricRow(label: "Exercise", current: vm.exerciseMinutes, goal: vm.exerciseGoal, unit: "min", color: .exerciseRing)
                        HomeMetricRow(label: "Stand",    current: vm.standHours,      goal: vm.standGoal,    unit: "hrs", color: .standRing)
                    } else {
                        HomeMetricRow(label: "Steps",    current: vm.steps,           goal: vm.stepsGoal,    unit: "steps", color: .stepsColor)
                        HomeMetricRow(label: "Exercise", current: vm.exerciseMinutes, goal: vm.exerciseGoal, unit: "min",   color: .exerciseRing)
                        HomeMetricRow(label: "Energy",   current: vm.activeEnergy,    goal: vm.energyGoal,   unit: "cal",   color: .activeEnergyColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Challenges Section (active + upcoming unified)

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FitnessSectionHeader(title: "Challenges")
                if vm.isRefreshingChallenges {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 20)

            if vm.isLoadingChallenges {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.activeItems) { item in
                        NavigationLink(value: item.challenge.id) {
                            ActiveChallengeRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(vm.upcomingChallenges) { challenge in
                        NavigationLink(value: challenge.id) {
                            PendingChallengeRow(challenge: challenge)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }


    // MARK: - Completed Section

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "Completed")
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(vm.completedChallenges) { challenge in
                    let rank = vm.completedItems.first(where: { $0.id == challenge.id })?.rank
                    NavigationLink(value: challenge.id) {
                        PendingChallengeRow(challenge: challenge, rank: rank, dimmed: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Toolbar Items

    private var profileButton: some View {
        Button { showProfile = true } label: {
            if let photo = profilePhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    //.frame(width: 30, height: 30)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    vm.showCompleted.toggle()
                }
            } label: {
                Label(
                    vm.showCompleted ? "Hide Completed" : "Show Completed",
                    systemImage: vm.showCompleted ? "eye.slash" : "eye"
                )
            }

            Divider()

            Button {
                newChallengeMode = .join
                showNewChallenge = true
            } label: {
                Label("Join with Code", systemImage: "qrcode.viewfinder")
            }

        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.secondaryText)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Floating Action Button

    private var fab: some View {
        Button {
            newChallengeMode = .create
            showNewChallenge = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.moveRing)
                .frame(width: 50, height: 50)
                .background {
                    Circle().fill(Color.cardBackground)
                    Circle().fill(Color.moveRing.opacity(0.18))
                }
        }
    }
}

// MARK: - Challenge Record Card (done / won)

struct ChallengeRecordCard: View {
    let done: Int
    let won: Int

    var body: some View {
        HStack(spacing: 0) {
            RecordCell(value: done, label: "Completed",
                       systemImage: "flag.checkered", tint: .exerciseRing)
                .frame(maxWidth: .infinity)
            Color.fitnessSeparator
                .frame(width: 0.5, height: 40)
            RecordCell(value: won, label: "Won",
                       systemImage: "trophy.fill", tint: .rankGold)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RecordCell: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text("\(value)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Record Card") {
    VStack(spacing: 16) {
        ChallengeRecordCard(done: 7, won: 3)
        ChallengeRecordCard(done: 1, won: 0)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Color.appBackground)
    .preferredColorScheme(.dark)
}
