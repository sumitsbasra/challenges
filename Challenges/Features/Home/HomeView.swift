import SwiftUI
import HealthKit
import CloudKit

// MARK: - ViewModel

@Observable
final class HomeViewModel {

    // MARK: Rings (from HealthKit)

    var ringData: RingData = RingData(
        moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
        stepsPct: 0, activeEnergyPct: 0, syncSource: .iphone
    )
    var steps: Double = 0
    var activeEnergy: Double = 0
    var exerciseMinutes: Double = 0
    var standHours: Double = 0
    var moveGoal: Double = 700
    var exerciseGoal: Double = 30
    var standGoal: Double = 12
    var stepsGoal: Double = 10_000
    var energyGoal: Double = 500
    var isLoadingRings = true
    var hasWatch: Bool = UserDefaults.standard.bool(forKey: "hasAppleWatch")

    // MARK: Challenges

    /// Active challenges with rank + points data.
    var activeItems: [TodayItem] = []
    /// Completed challenges with final rank data.
    var completedItems: [TodayItem] = []
    /// Upcoming (pending) challenges — shown below active.
    var upcomingChallenges: [Challenge] = []
    /// Completed challenges — hidden unless showCompleted = true.
    var completedChallenges: [Challenge] = []
    /// All challenges flat — used for deep-link lookups.
    var allChallenges: [Challenge] = []

    /// True only on the very first load when there is no cached data.
    var isLoadingChallenges = false
    /// True while a background refresh is in progress (cached data is already shown).
    var isRefreshingChallenges = false
    var showCompleted = false
    var error: String? = nil

    private let ck = CloudKitManager.shared

    // MARK: - Load

    @MainActor
    func load(userID: String) async {
        await loadRings()
        await loadChallenges(userID: userID)
    }

    // MARK: - Rings

    @MainActor
    func loadRings() async {
        isLoadingRings = true
        defer { isLoadingRings = false }

        // Re-detect Watch every load to catch stale flags from onboarding.
        let detected = await WatchDetector().detectAppleWatch()
        if detected != hasWatch {
            hasWatch = detected
            UserDefaults.standard.set(detected, forKey: "hasAppleWatch")
            if var user = UserSession.shared.currentUser {
                user.hasAppleWatch = detected
                UserSession.shared.update(user: user)
                try? await CloudKitManager.shared.saveUser(user)
            }
        }

        let fetcher = ActivityDataFetcher()
        let today = Date()
        let calendar = Calendar.current

        if hasWatch {
            let summaries = await fetcher.activitySummaries(from: today, to: today)
            let key = calendar.startOfDay(for: today)
            if let summary = summaries[key] {
                let moveGoal  = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                let moveDone  = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                let exGoal    = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
                let exDone    = summary.appleExerciseTime.doubleValue(for: .minute())
                let standGoal = summary.appleStandHoursGoal.doubleValue(for: .count())
                let standDone = summary.appleStandHours.doubleValue(for: .count())

                activeEnergy    = moveDone
                exerciseMinutes = exDone
                standHours      = standDone
                self.moveGoal     = max(moveGoal, 1)
                self.exerciseGoal = max(exGoal, 1)
                self.standGoal    = max(standGoal, 1)
                ringData = RingData(
                    moveRingPct:     moveGoal  > 0 ? moveDone  / moveGoal  : 0,
                    exerciseRingPct: exGoal    > 0 ? exDone    / exGoal    : 0,
                    standRingPct:    standGoal > 0 ? standDone / standGoal : 0,
                    stepsPct: 0, activeEnergyPct: 0,
                    syncSource: .watch
                )
            }
        } else {
            async let stepsTask  = fetcher.steps(on: today)
            async let energyTask = fetcher.activeEnergy(on: today)
            let (s, e) = await (stepsTask, energyTask)
            steps        = s
            activeEnergy = e
            let goalResolver  = GoalResolver()
            let stepsGoalVal  = goalResolver.stepsGoal
            let energyGoalVal = goalResolver.activeEnergyGoal
            self.stepsGoal  = stepsGoalVal
            self.energyGoal = energyGoalVal
            ringData = RingData(
                moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                stepsPct:        stepsGoalVal  > 0 ? s / stepsGoalVal  : 0,
                activeEnergyPct: energyGoalVal > 0 ? e / energyGoalVal : 0,
                syncSource: .iphone
            )
        }
    }

    // MARK: - Challenges

    @MainActor
    func loadChallenges(userID: String) async {
        // Populate from cache immediately — no spinner if we have data.
        if let cached = ChallengeCache.load(userID: userID) {
            // Apply local status transitions to cached data so the badge text is
            // correct even before the network fetch completes.
            let locallyTransitioned = applyLocalTransitions(cached.challenges, fireCloudKit: false)
            applyAll(locallyTransitioned, activeItems: cached.activeItems, completedItems: [])
            isRefreshingChallenges = true
        } else {
            isLoadingChallenges = true
        }

        defer {
            isLoadingChallenges = false
            isRefreshingChallenges = false
        }

        do {
            let fetched = try await ck.fetchChallenges(forUserID: userID)
            // Immediately transition any challenges whose window has opened or closed,
            // and fire CloudKit updates in the background so other clients see the change.
            let all = applyLocalTransitions(fetched, fireCloudKit: true)
            var seenIDs = Set<String>([userID])
            let active    = try await buildRankedItems(from: all, status: .active,    userID: userID, seenIDs: &seenIDs)
            let completed = try await buildRankedItems(from: all, status: .completed, userID: userID, seenIDs: &seenIDs)
            applyAll(all, activeItems: active, completedItems: completed)
            ChallengeCache.save(challenges: all, activeItems: active, userID: userID)
            // Prune avatars for users no longer in any of our challenges.
            Task.detached { AvatarCache.pruneStale(keepingUserIDs: seenIDs) }
            SpotlightIndexer.index(all)
            Task { await NotificationScheduler.reschedule(for: all) }
        } catch {
            let ckError = error as? CKError
            if ckError?.code == .networkUnavailable || ckError?.code == .networkFailure {
                self.error = "No internet connection. Showing cached data."
            } else if ckError?.code == .notAuthenticated {
                self.error = "iCloud sign-in required. Check Settings → iCloud."
            } else {
                self.error = "Couldn't refresh. Pull down to try again."
            }
        }
    }

    @MainActor
    private func applyAll(_ all: [Challenge], activeItems: [TodayItem], completedItems: [TodayItem]) {
        allChallenges        = all
        self.activeItems     = activeItems
        self.completedItems  = completedItems
        upcomingChallenges   = all.filter { $0.status == .pending }
        completedChallenges  = all.filter { $0.status == .completed }
    }

    /// Patches a challenge's title across every in-memory collection — no CloudKit fetch needed.
    @MainActor
    func applyRename(id: String, title: String) {
        func patchChallenge(_ c: inout Challenge) { if c.id == id { c.title = title } }
        for i in allChallenges.indices       { patchChallenge(&allChallenges[i]) }
        for i in upcomingChallenges.indices  { patchChallenge(&upcomingChallenges[i]) }
        for i in completedChallenges.indices { patchChallenge(&completedChallenges[i]) }
        activeItems    = activeItems.map    { patchItem($0, id: id) { c in c.title = title } }
        completedItems = completedItems.map { patchItem($0, id: id) { c in c.title = title } }
    }

    /// Patches a challenge's dates across every in-memory collection — no CloudKit fetch needed.
    @MainActor
    func applyDateUpdate(id: String, startDate: Date, endDate: Date) {
        func patchChallenge(_ c: inout Challenge) {
            if c.id == id { c.startDate = startDate; c.endDate = endDate }
        }
        for i in allChallenges.indices       { patchChallenge(&allChallenges[i]) }
        for i in upcomingChallenges.indices  { patchChallenge(&upcomingChallenges[i]) }
        for i in completedChallenges.indices { patchChallenge(&completedChallenges[i]) }
        activeItems    = activeItems.map    { patchItem($0, id: id) { c in c.startDate = startDate; c.endDate = endDate } }
        completedItems = completedItems.map { patchItem($0, id: id) { c in c.startDate = startDate; c.endDate = endDate } }
    }

    /// Applies `pending → active` and `active → completed` transitions based on the
    /// current date. When `fireCloudKit` is true, writes each transition to CloudKit in
    /// the background — used on a fresh network fetch so other clients see the update.
    @MainActor
    private func applyLocalTransitions(_ challenges: [Challenge], fireCloudKit: Bool) -> [Challenge] {
        let now = Date()
        var result = challenges
        for i in result.indices {
            let c = result[i]
            if c.status == .pending && c.startDate <= now {
                result[i].status = .active
                if fireCloudKit {
                    let id = c.id
                    Task { try? await CloudKitManager.shared.updateChallengeStatus(id, status: .active) }
                }
            } else if c.status == .active && c.endDate < now {
                result[i].status = .completed
                if fireCloudKit {
                    let id = c.id
                    Task { try? await CloudKitManager.shared.updateChallengeStatus(id, status: .completed) }
                }
            }
        }
        return result
    }

    /// Returns a new TodayItem with the challenge mutated by `modify`, or the original if IDs don't match.
    private func patchItem(_ item: TodayItem, id: String, modify: (inout Challenge) -> Void) -> TodayItem {
        guard item.id == id else { return item }
        var c = item.challenge
        modify(&c)
        return TodayItem(
            id: item.id, challenge: c, rank: item.rank,
            participantCount: item.participantCount,
            todayPoints: item.todayPoints, totalPoints: item.totalPoints
        )
    }

    @MainActor
    private func buildRankedItems(from all: [Challenge], status: ChallengeStatus,
                                  userID: String,
                                  seenIDs: inout Set<String>) async throws -> [TodayItem] {
        let challenges = all.filter { $0.status == status }
        var items: [TodayItem] = []
        for challenge in challenges {
            var parts  = try await ck.fetchParticipations(challengeID: challenge.id)
            let scores = try await ck.fetchDailyScores(challengeID: challenge.id)

            for i in parts.indices {
                parts[i].dailyScores = scores
                    .filter  { $0.participationID == parts[i].id }
                    .sorted  { $0.date < $1.date }
            }

            let ranked = ScoreAggregator.ranked(parts)
            // Collect every participant's user ID so we can prune stale avatar files.
            seenIDs.formUnion(ranked.map { $0.user.id })
            guard let mine = ranked.first(where: { $0.user.id == userID }) else { continue }

            let todayPts = mine.dailyScores
                .first(where: { Calendar.current.isDateInToday($0.date) })?.points ?? 0

            items.append(TodayItem(
                id:               challenge.id,
                challenge:        challenge,
                rank:             mine.rank,
                participantCount: ranked.count,
                todayPoints:      todayPts,
                totalPoints:      mine.totalPoints
            ))
        }
        return items
    }
}

// MARK: - Home View

struct HomeView: View {
    @Environment(UserSession.self) private var session
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
            // Kick off background work once data is loaded.
            await SyncCoordinator.shared.syncCurrentChallenges()
            BackgroundTaskScheduler.scheduleAppRefresh()
            Task { await NotificationScheduler.reschedule(for: vm.allChallenges) }
            let activeIDs = vm.allChallenges.filter { $0.status == .active }.map { $0.id }
            await CloudKitManager.shared.registerSubscriptions(forActiveChallengeIDs: activeIDs)
        }
        .refreshable {
            guard let userID = session.userID else { return }
            await vm.load(userID: userID)
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
        let hasChallenges = !vm.activeItems.isEmpty || !vm.upcomingChallenges.isEmpty
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
                    challengesSection
                    if vm.showCompleted && !vm.completedChallenges.isEmpty {
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
                        TwoRingView(ringData: vm.ringData, size: 132)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if vm.hasWatch {
                        HomeMetricRow(label: "Move",     current: vm.activeEnergy,    goal: vm.moveGoal,     unit: "cal", color: .moveRing)
                        HomeMetricRow(label: "Exercise", current: vm.exerciseMinutes, goal: vm.exerciseGoal, unit: "min", color: .exerciseRing)
                        HomeMetricRow(label: "Stand",    current: vm.standHours,      goal: vm.standGoal,    unit: "hrs", color: .standRing)
                    } else {
                        HomeMetricRow(label: "Steps",  current: vm.steps,        goal: vm.stepsGoal,  unit: "steps", color: .stepsColor)
                        HomeMetricRow(label: "Energy", current: vm.activeEnergy, goal: vm.energyGoal, unit: "cal",   color: .activeEnergyColor)
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

// MARK: - Active Challenge Row (rank + points)

private struct ActiveChallengeRow: View {
    let item: TodayItem

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.challenge.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text("+\(Int(item.todayPoints)) pts today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(item.daysRemainingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                rankBadge
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.trailing, 16)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rankBadge: some View {
        Group {
            switch item.rank {
            case 1:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankGold)
            case 2:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankSilver)
            case 3:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankBronze)
            default:
                Text("#\(item.rank)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Pending / Completed Challenge Row

private struct PendingChallengeRow: View {
    let challenge: Challenge
    var rank: Int? = nil
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            // Title + date
            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(.headline)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)

            Spacer(minLength: 8)

            // Right badge + chevron
            HStack(spacing: 8) {
                rightBadge
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.trailing, 16)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(dimmed ? 0.65 : 1)
    }

    @ViewBuilder
    private var rightBadge: some View {
        switch challenge.status {
        case .pending:
            let days = max(0, Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: challenge.startDate)).day ?? 0)
            Text(days == 0 ? "Starts today" : "Starts in \(days) day\(days == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.stepsColor)
        case .completed:
            if let r = rank {
                switch r {
                case 1:
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.rankGold)
                case 2:
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.rankSilver)
                case 3:
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.rankBronze)
                default:
                    Text("#\(r)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        case .active:
            EmptyView()
        }
    }

    private var dateRange: String {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())
        let startYear = cal.component(.year, from: challenge.startDate)
        let endYear   = cal.component(.year, from: challenge.endDate)

        let start = challenge.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end: String
        if endYear != thisYear || startYear != endYear {
            end = challenge.endDate.formatted(.dateTime.month(.abbreviated).day().year())
        } else {
            end = challenge.endDate.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(start) – \(end)"
    }

}

// MARK: - Challenge Card Previews

#Preview("Challenge Cards") {
    ZStack {
        Color.appBackground.ignoresSafeArea()

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {

                // ── Active ────────────────────────────────────────────
                cardGroup(title: "Active") {
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 1, today: 420,  total: 3_200, daysLeft: 4))
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 2, today: 190,  total: 2_810, daysLeft: 4))
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 3, today: 0,    total: 2_390, daysLeft: 1))
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 5, today: 305,  total: 1_540, daysLeft: 6))
                    ActiveChallengeRow(item: CardPreviewData.active1Item(rank: 8, today: 0,    total: 0,     daysLeft: 0))
                }

                // ── Upcoming ──────────────────────────────────────────
                cardGroup(title: "Upcoming") {
                    PendingChallengeRow(challenge: CardPreviewData.pending1)
                    PendingChallengeRow(challenge: CardPreviewData.pending2)
                    PendingChallengeRow(challenge: CardPreviewData.pending3)
                }

                // ── Completed ─────────────────────────────────────────
                cardGroup(title: "Completed") {
                    PendingChallengeRow(challenge: CardPreviewData.completed1, rank: 1, dimmed: true)
                    PendingChallengeRow(challenge: CardPreviewData.completed2, rank: 2, dimmed: true)
                    PendingChallengeRow(challenge: CardPreviewData.completed3, rank: 3, dimmed: true)
                    PendingChallengeRow(challenge: CardPreviewData.completed4, rank: 5, dimmed: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }
    .navigationTitle("Saturday, Mar 21")
    .preferredColorScheme(.dark)
}

@ViewBuilder
private func cardGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.fitnessHeader())
            .padding(.horizontal, 4)
        content()
    }
}

private enum CardPreviewData {
    static let cal = Calendar.current
    static let now = Date()

    static func date(adding days: Int) -> Date {
        cal.date(byAdding: .day, value: days, to: now)!
    }

    static func challenge(title: String, status: ChallengeStatus, start: Date, end: Date) -> Challenge {
        Challenge(id: UUID().uuidString, title: title, creatorID: "me",
                  startDate: start, endDate: end, status: status,
                  inviteCode: "ABC123", maxParticipants: 20, createdAt: now)
    }

    static func active1Item(rank: Int, today: Double, total: Double, daysLeft: Int) -> TodayItem {
        let end = date(adding: daysLeft)
        let c = challenge(title: "Summer Step Challenge", status: .active,
                          start: date(adding: -7), end: end)
        return TodayItem(id: c.id, challenge: c, rank: rank,
                         participantCount: 8, todayPoints: today, totalPoints: total)
    }

    // Active challenges (different instances so NavigationLink values are unique)
    static let active1 = challenge(title: "Summer Step Challenge", status: .active, start: date(adding: -7), end: date(adding: 4))
    static let active2 = challenge(title: "Spring Fitness Blitz",  status: .active, start: date(adding: -3), end: date(adding: 4))
    static let active3 = challenge(title: "Office Challenge",      status: .active, start: date(adding: -6), end: date(adding: 1))
    static let active4 = challenge(title: "Monthly Move Goals",    status: .active, start: date(adding: -1), end: date(adding: 6))
    static let active5 = challenge(title: "Quick Sprint",          status: .active, start: date(adding: -7), end: date(adding: 0))

    // Upcoming
    static let pending1 = challenge(title: "Weekend Warrior",      status: .pending, start: date(adding: 1),  end: date(adding: 8))
    static let pending2 = challenge(title: "April Steps",          status: .pending, start: date(adding: 7),  end: date(adding: 14))
    static let pending3 = challenge(title: "New Year Kickoff",     status: .pending, start: date(adding: 285), end: date(adding: 292))

    // Completed
    static let completed1 = challenge(title: "March Madness",     status: .completed, start: date(adding: -14), end: date(adding: -7))
    static let completed2 = challenge(title: "Valentine's Run",   status: .completed, start: date(adding: -35), end: date(adding: -28))
    static let completed3 = challenge(title: "Winter Steps",      status: .completed, start: date(adding: -60), end: date(adding: -53))
    static let completed4 = challenge(title: "New Year Challenge", status: .completed, start: date(adding: -90), end: date(adding: -83))
}

// MARK: - Metric Row

private struct HomeMetricRow: View {
    let label: String
    let current: Double
    let goal: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Label always grey
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            // Number line: "457/700 CAL" — all ring color, unit smaller
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(current).formatted())/\(Int(goal).formatted())")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(unit.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .tracking(0.3)
            }
        }
    }
}

// MARK: - Mock Data (Debug only)

#if DEBUG

enum MockRingPreset: String, CaseIterable {
    case normal = "Normal (<100%)"
    case over   = "Over 100%"
    case empty  = "Empty"
}

extension HomeViewModel {
    @MainActor
    func loadMockData(ringPreset: MockRingPreset = .over) {
        let cal = Calendar.current
        let now = Date()
        func date(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: now)! }

        func makeChallenge(_ title: String, status: ChallengeStatus, start: Int, end: Int) -> Challenge {
            Challenge(id: UUID().uuidString, title: title, creatorID: "mock-me",
                      startDate: date(start), endDate: date(end),
                      status: status, inviteCode: "MOCK01",
                      maxParticipants: 10, createdAt: now)
        }

        func makeItem(_ c: Challenge, rank: Int, participants: Int, today: Double, total: Double) -> TodayItem {
            TodayItem(id: c.id, challenge: c, rank: rank,
                      participantCount: participants, todayPoints: today, totalPoints: total)
        }

        // Rings
        switch ringPreset {
        case .normal:
            ringData = RingData(moveRingPct: 0.74, exerciseRingPct: 0.60, standRingPct: 0.83,
                                stepsPct: 0.68, activeEnergyPct: 0.74, syncSource: .watch)
        case .over:
            ringData = RingData(moveRingPct: 1.45, exerciseRingPct: 2.0, standRingPct: 1.25,
                                stepsPct: 1.3, activeEnergyPct: 1.45, syncSource: .watch)
        case .empty:
            ringData = RingData(moveRingPct: 0.04, exerciseRingPct: 0.0, standRingPct: 0.08,
                                stepsPct: 0.03, activeEnergyPct: 0.04, syncSource: .watch)
        }
        hasWatch        = true
        activeEnergy    = ringData.moveRingPct    * moveGoal
        exerciseMinutes = ringData.exerciseRingPct * exerciseGoal
        standHours      = ringData.standRingPct   * standGoal
        isLoadingRings  = false

        // Challenges
        let a1 = makeChallenge("Spring Step Challenge", status: .active,    start: -3, end: 4)
        let a2 = makeChallenge("Ring Closers",          status: .active,    start: -1, end: 6)
        let u1 = makeChallenge("Weekend Warrior",       status: .pending,   start:  2, end: 9)
        let u2 = makeChallenge("Office Rivals",         status: .pending,   start:  5, end: 12)
        let c1 = makeChallenge("March Madness",         status: .completed, start: -10, end: -3)

        activeItems         = [makeItem(a1, rank: 1, participants: 5, today: 420,  total: 3_200),
                               makeItem(a2, rank: 3, participants: 8, today: 185,  total: 1_940)]
        completedItems      = [makeItem(c1, rank: 2, participants: 6, today: 0,    total: 8_750)]
        upcomingChallenges  = [u1, u2]
        completedChallenges = [c1]
        allChallenges       = [a1, a2, u1, u2, c1]
        isLoadingChallenges = false
    }
}

#endif
