import SwiftUI
import Intents
import Charts

struct ChallengeDetailView: View {
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: ChallengeDetailViewModel
    @State private var showDeleteConfirm  = false
    @State private var showLeaveConfirm   = false
    @State private var showEditChallenge  = false
    @State private var selectedParticipant: Participation?

    /// Always reads from the ViewModel so live status transitions (pending → active, etc.)
    /// are immediately reflected in the UI without re-navigating.
    private var challenge: Challenge { vm.challenge }

    init(challenge: Challenge) {
        _vm = State(initialValue: ChallengeDetailViewModel(challenge: challenge))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 1. Status banner
                statusBanner
                    .padding(.top, 8)

                // 2. Results moment for completed challenges (winner + placement).
                if challenge.status == .completed, let s = vm.standing {
                    ResultsHeaderCard(
                        standing: s,
                        winnerName: vm.rankedParticipations.first.map {
                            $0.user.id == session.userID ? "You" : $0.user.displayName
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }

                // 2b. Overall stats for completed challenges — what everyone did together.
                // Gated on having real data, not on leaderboardLoaded: cached
                // participations already carry scores, so the card renders instantly
                // on reopen instead of waiting for a fresh CloudKit round trip.
                if challenge.status == .completed,
                   vm.groupContributions.contains(where: {
                       $0.steps > 0 || $0.distanceMeters > 0 || $0.workouts > 0
                   }) {
                    GroupTotalsCard(contributions: vm.groupContributions,
                                    currentUserID: session.userID ?? "")
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                }

                // 3. Activity hero card (current user's rings)
                if let me = vm.currentUserParticipation, challenge.status == .active {
                    MyProgressView(participation: me)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                    PointsCardView(participation: me)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                // 4. Score history chart — active and completed challenges with data
                if challenge.status != .pending,
                   let me = vm.currentUserParticipation,
                   !me.dailyScores.isEmpty {
                    ScoreHistoryChart(participation: me, challenge: challenge)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                }

                // 5. Pending: lead with the invite so people get in before it starts.
                if challenge.status == .pending {
                    inviteSection
                        .padding(.top, 24)
                }

                // 6. Leaderboard — all statuses (pending shows who's joined, active/completed shows ranks)
                leaderboardSection
                    .padding(.top, 28)

                // 7. Active: invite below the leaderboard. Any participant can share.
                if challenge.status == .active {
                    inviteSection
                        .padding(.top, 28)
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let error = vm.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                    .onTapGesture { vm.error = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: vm.error)
            }
        }
        .navigationTitle(vm.challenge.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Share button
                if challenge.status != .completed,
                   challenge.creatorID == (session.userID ?? ""),
                   let joinURL = URL(string: "challenges://join/\(challenge.inviteCode)") {
                    ShareLink(
                        item: joinURL,
                        message: Text("Join my fitness challenge! Code: \(challenge.inviteCode)")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }

                // … menu
                Menu {
                    if challenge.creatorID == (session.userID ?? "") {
                        Button {
                            showEditChallenge = true
                        } label: {
                            Label("Edit Challenge", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Challenge", systemImage: "trash")
                                .tint(.red)
                        }
                    } else {
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label("Leave Challenge", systemImage: "rectangle.portrait.and.arrow.right")
                                .tint(.red)
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
                    do {
                        try await vm.deleteChallenge()
                        dismiss()
                    } catch {
                        vm.error = "Couldn't delete challenge. Try again."
                    }
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
                    do {
                        try await vm.leaveChallenge(userID: userID)
                        dismiss()
                    } catch {
                        vm.error = "Couldn't leave challenge. Try again."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $selectedParticipant) { p in
            ParticipantDetailSheet(
                participation: p,
                challenge: challenge,
                isCurrentUser: p.user.id == session.userID,
                vm: vm
            )
        }
        .sheet(isPresented: $showEditChallenge) {
            EditChallengeSheet(challenge: vm.challenge) { title, start, end in
                Task {
                    do {
                        try await vm.update(title: title, startDate: start, endDate: end)
                    } catch {
                        vm.error = "Couldn't save changes. Try again."
                    }
                }
            }
        }
        .task { await vm.load() }
        .task { await vm.loadReactions() }
        .task { await vm.loadGroupWorkouts() }
        .refreshable { await vm.refresh() }
        // Re-sync when the app returns to the foreground. The Apple Watch batches
        // activity summaries and may not have pushed them to the iPhone HealthKit
        // store when the detail first loaded. This picks up past-day scores that
        // were 0 at load time but are now correct.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, challenge.status == .active else { return }
            Task { await vm.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dailyScoreDidUpdate)) { _ in
            Task { await vm.handleScoreUpdate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reactionReceived)) { note in
            guard note.userInfo?["challengeID"] as? String == challenge.id else { return }
            Task { await vm.loadReactions() }
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
                Text("\(vm.challenge.startDate.formatted(.dateTime.month(.abbreviated).day())) – \(vm.challenge.endDate.formatted(.dateTime.month(.abbreviated).day()))")
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
            FitnessSectionHeader(title: challenge.status == .pending ? "Participants" : "Leaderboard")
                .padding(.horizontal, 20)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.cardBackground)

                if vm.isLoading && vm.participations.isEmpty {
                    ProgressView()
                        .padding(32)
                } else if vm.rankedParticipations.isEmpty {
                    VStack(spacing: 6) {
                        Text(challenge.status == .pending ? "Waiting for participants." : "No participants yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if challenge.status == .pending {
                            Text("Share your invite code to get people in.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.rankedParticipations.enumerated()), id: \.element.id) { idx, p in
                            let isMe = p.user.id == session.userID
                            let row = LeaderboardRowView(
                                participation: p,
                                isCurrentUser: isMe,
                                showRank: challenge.status != .pending,
                                reactionEmojis: vm.todaysReactionsByParticipation[p.id] ?? []
                            )
                            // Tap a participant to see their score breakdown — only once
                            // there are scores to show (active/completed, not pending).
                            if challenge.status != .pending {
                                Button { selectedParticipant = p } label: { row }
                                    .buttonStyle(.plain)
                            } else {
                                row
                            }
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
        case .pending:   return .stepsColor
        case .completed: return .secondaryText
        case .active:
            let text = vm.countdownText
            if text == "Ends today" || text == "Ends tomorrow" { return .moveRing }
            return .exerciseRing
        }
    }
}

// MARK: - Rank formatting helpers

/// 1 → "1st", 2 → "2nd", 3 → "3rd", 11 → "11th", etc.
func rankOrdinal(_ n: Int) -> String {
    let ones = n % 10, tens = (n / 10) % 10
    let suffix: String
    if tens == 1 { suffix = "th" }
    else { switch ones { case 1: suffix = "st"; case 2: suffix = "nd"; case 3: suffix = "rd"; default: suffix = "th" } }
    return "\(n)\(suffix)"
}

func rankMedal(_ rank: Int) -> String {
    switch rank { case 1: return "🥇"; case 2: return "🥈"; case 3: return "🥉"; default: return "" }
}


// MARK: - Group Totals Card (completed)

/// What the whole group did across the challenge — steps, distance, workouts — with
/// each participant's share drawn as a colored segment. Small groups (≤4) get stacked
/// per-person bars with an avatar legend; larger groups fall back to a single bar
/// showing the viewer's share, since 10+ hairline segments read as noise.
struct GroupTotalsCard: View {
    let contributions: [ChallengeDetailViewModel.MemberContribution]
    let currentUserID: String

    @AppStorage("preferredUnits") private var preferredUnits = "Imperial"

    /// Segment colors assigned by leaderboard order.
    private static let palette: [Color] = [.exerciseRing, .moveRing, .standRing, .stepsColor]
    private static let stackedLimit = 4

    private var isStacked: Bool { contributions.count <= Self.stackedLimit }
    private var useMetric: Bool { preferredUnits == "Metric" }

    private var totalSteps: Double { contributions.map(\.steps).reduce(0, +) }
    private var totalDistance: Double { contributions.map(\.distanceMeters).reduce(0, +) }
    private var totalWorkouts: Int { contributions.map(\.workouts).reduce(0, +) }

    private var me: ChallengeDetailViewModel.MemberContribution? {
        contributions.first { $0.user.id == currentUserID }
    }

    private func color(at index: Int) -> Color {
        Self.palette[index % Self.palette.count]
    }

    private func distanceText(_ meters: Double) -> String {
        useMetric
            ? String(format: "%.1f km", meters / 1000)
            : String(format: "%.1f mi", meters / 1609.344)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "Overall Stats")
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 14) {
                metricRow(label: "Steps",
                          total: Int(totalSteps).formatted(),
                          values: contributions.map(\.steps),
                          myText: me.map { Int($0.steps).formatted() })
                metricRow(label: "Distance",
                          total: distanceText(totalDistance),
                          values: contributions.map(\.distanceMeters),
                          myText: me.map { distanceText($0.distanceMeters) })
                metricRow(label: "Workouts",
                          total: totalWorkouts.formatted(),
                          values: contributions.map { Double($0.workouts) },
                          myText: me.map { $0.workouts.formatted() })

                if isStacked {
                    legend
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Legend — one avatar per participant, ringed in their segment color.

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(Array(contributions.enumerated()), id: \.element.id) { idx, member in
                avatar(for: member.user)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(color(at: idx), lineWidth: 1))
                    .accessibilityLabel(member.user.displayName)
            }
        }
    }

    private func avatar(for user: AppUser) -> some View {
        Circle()
            .fill(Color.cardInset)
            .overlay {
                if let img = AvatarCache.load(userID: user.id)
                    ?? user.avatarURL.flatMap({ UIImage(contentsOfFile: $0.path) }) {
                    Image(uiImage: img).resizable().scaledToFill().clipShape(Circle())
                } else {
                    Text(user.displayName.prefix(1).uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
    }

    // MARK: Metric rows

    private func metricRow(label: String, total: String, values: [Double], myText: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(total)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            if isStacked {
                stackedBar(values: values)
            } else if let me, let myText {
                // Viewer's share of the group. If the viewer isn't a participant
                // there's no share to draw — the label/total line stands alone.
                viewerBar(values: values)
                Text("\(me.user.displayName) \(myText)")
                    .font(.caption2)
                    .foregroundStyle(Color.exerciseRing)
            }
        }
    }

    /// One colored segment per participant, proportional to their share.
    private func stackedBar(values: [Double]) -> some View {
        let total = values.reduce(0, +)
        return GeometryReader { geo in
            if total > 0 {
                HStack(spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { idx, value in
                        if value > 0 {
                            Rectangle()
                                .fill(color(at: idx))
                                .frame(width: max(2, (geo.size.width - CGFloat(values.count - 1) * 2) * value / total))
                        }
                    }
                }
                .clipShape(Capsule())
            } else {
                Capsule().fill(Color.primary.opacity(0.08))
            }
        }
        .frame(height: 8)
    }

    /// Large-group fallback: a single bar showing the viewer's share of the group.
    private func viewerBar(values: [Double]) -> some View {
        let total = values.reduce(0, +)
        let mine = me.flatMap { m in contributions.firstIndex(where: { $0.id == m.id }).map { values[$0] } } ?? 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if total > 0, mine > 0 {
                    Capsule()
                        .fill(Color.exerciseRing)
                        .frame(width: max(6, geo.size.width * mine / total))
                }
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Results Header Card (completed)

struct ResultsHeaderCard: View {
    let standing: ChallengeDetailViewModel.Standing
    /// Display name of the winner ("You" if it's the current user); nil if unknown.
    let winnerName: String?

    var body: some View {
        VStack(spacing: 10) {
            if let winnerName {
                Text("🏆").font(.system(size: 34))
                Text("\(winnerName) won")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Text("You finished \(rankOrdinal(standing.rank)) \(rankMedal(standing.rank))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color.rankGold.opacity(0.14), Color.cardBackground],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Participant Detail Sheet

/// Tapping a leaderboard row opens this — a participant's rank, total, score history,
/// and daily breakdown. Reuses the same chart/breakdown components as the hero card.
private struct ParticipantDetailSheet: View {
    let participation: Participation
    let challenge: Challenge
    let isCurrentUser: Bool
    /// Enables the reaction bar; nil (e.g. previews) hides it.
    var vm: ChallengeDetailViewModel? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var workouts: [WorkoutSummary] = []

    private var name: String { isCurrentUser ? "You" : participation.user.displayName }

    private func loadWorkouts() async {
        let all = (try? await CloudKitManager.shared.fetchWorkouts(challengeID: challenge.id)) ?? []
        workouts = all
            .filter { $0.participationID == participation.id }
            .sorted { $0.date > $1.date }
    }

    // MARK: Derived stats (past days only)

    private var scores: [DailyScore] {
        participation.dailyScores.filter { $0.date <= Date() }
    }
    private var bestDay: Double { scores.map(\.points).max() ?? 0 }
    private var activeDays: Int { scores.filter { $0.points > 0 }.count }
    private var dailyAvg: Double {
        activeDays > 0 ? scores.map(\.points).reduce(0, +) / Double(activeDays) : 0
    }
    private var totalSteps: Double { scores.map { $0.ringData.totalSteps }.reduce(0, +) }
    private var totalDistance: Double { scores.map { $0.ringData.distanceMeters }.reduce(0, +) }

    private var distanceText: String {
        Measurement(value: totalDistance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated,
                                    usage: .road,
                                    numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if canReact {
                        reactionBar
                    }

                    if scores.isEmpty {
                        ContentUnavailableView(
                            "No activity yet",
                            systemImage: "figure.run",
                            description: Text("Scores will appear here once \(isCurrentUser ? "you start" : "they start") earning points.")
                        )
                        .padding(.top, 40)
                    } else {
                        statsGrid
                        ScoreHistoryChart(participation: participation, challenge: challenge,
                                          title: isCurrentUser ? "My Points" : "\(participation.user.displayName)'s Points")
                        DailyBreakdownView(participation: participation, challenge: challenge)
                    }

                    if !workouts.isEmpty {
                        workoutsSection
                    }
                }
                .padding(16)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadWorkouts() }
        }
        .presentationDetents([.large])
    }

    // MARK: Reactions

    private var canReact: Bool {
        challenge.status == .active && !isCurrentUser && vm?.currentUserParticipation != nil
    }

    private var sentEmoji: String? {
        vm?.myReactionToday(to: participation.id)
    }

    private var reactionBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(Reaction.allowedEmojis, id: \.self) { emoji in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await vm?.sendReaction(emoji, to: participation) }
                    } label: {
                        Text(emoji)
                            .font(.system(size: 22))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.cardInset, in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    sentEmoji == emoji ? Color.exerciseRing : .clear,
                                    lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(sentEmoji.map { "\($0) sent. Tap another to swap." }
                 ?? "One reaction per day. Tap another to swap.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Workouts

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "Workouts")
            VStack(spacing: 0) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { idx, workout in
                    WorkoutRow(workout: workout)
                    if idx < workouts.count - 1 {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.title2.bold())
                HStack(spacing: 5) {
                    Image(systemName: participation.hasAppleWatch ? "applewatch" : "iphone")
                        .font(.system(size: 11))
                    Text(participation.hasAppleWatch ? "Apple Watch" : "iPhone")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(Int(participation.totalPoints).formatted())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.moveRing)
                Text("points").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var avatar: some View {
        Circle()
            .fill(Color.cardInset)
            .frame(width: 52, height: 52)
            .overlay {
                if let img = AvatarCache.load(userID: participation.user.id)
                    ?? participation.user.avatarURL.flatMap({ UIImage(contentsOfFile: $0.path) }) {
                    Image(uiImage: img).resizable().scaledToFill().clipShape(Circle())
                } else {
                    Text(name.prefix(1).uppercased())
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
    }

    // MARK: Stats grid

    private var statsGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            StatTile(value: Int(bestDay).formatted(), label: "Best day",
                     systemImage: "flame.fill", tint: .moveRing)
            StatTile(value: Int(dailyAvg).formatted(), label: "Avg / day",
                     systemImage: "chart.bar.fill", tint: .exerciseRing)
            StatTile(value: Int(totalSteps).formatted(), label: "Total steps",
                     systemImage: "figure.walk", tint: .activeEnergyColor)
            StatTile(value: distanceText, label: "Total distance",
                     systemImage: "location.fill", tint: .moveRing)
        }
    }
}

// MARK: - Workout Row

private struct WorkoutRow: View {
    let workout: WorkoutSummary

    private var detail: String {
        guard workout.distance > 0 else { return "\(Int(workout.activeEnergy)) cal" }
        // Always show a fraction of a mile/km (never feet), respecting the user's
        // Profile units preference, falling back to locale.
        let usesMetric: Bool
        if UserDefaults.standard.object(forKey: "preferredUnits") != nil {
            usesMetric = UserDefaults.standard.string(forKey: "preferredUnits") == "Metric"
        } else {
            usesMetric = Locale.current.measurementSystem != .us
        }
        return usesMetric
            ? String(format: "%.1f km", workout.distance / 1000)
            : String(format: "%.1f mi", workout.distance / 1609.344)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.moveRing)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.subheadline.weight(.semibold))
                Text(workout.date.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(detail)
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(workout.durationText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Stat Tile

private struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Edit Challenge Sheet

private struct EditChallengeSheet: View {
    let challenge: Challenge
    let onSave: (String, Date, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title:     String
    @State private var startDate: Date
    @State private var endDate:   Date
    @FocusState private var titleFocused: Bool

    init(challenge: Challenge, onSave: @escaping (String, Date, Date) -> Void) {
        self.challenge = challenge
        self.onSave    = onSave
        _title     = State(initialValue: challenge.title)
        _startDate = State(initialValue: challenge.startDate)
        _endDate   = State(initialValue: challenge.endDate)
    }

    private var isPending: Bool { challenge.status == .pending }
    private var canSave:   Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private var minStart: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return Calendar.current.startOfDay(for: tomorrow)
    }
    private var minEnd: Date {
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        return Calendar.current.startOfDay(for: nextDay)
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Name ──────────────────────────────────────────────
                Section("Name") {
                    TextField("Challenge name", text: $title)
                        .textInputAutocapitalization(.words)
                        .focused($titleFocused)
                }

                // ── Start Date (pending only) ──────────────────────
                if isPending {
                    Section("Start Date") {
                        DatePicker(
                            "Start",
                            selection: $startDate,
                            in: minStart...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .tint(.moveRing)
                        .onChange(of: startDate) { _, _ in
                            if endDate < minEnd { endDate = minEnd }
                        }
                    }
                }

                // ── End Date ──────────────────────────────────────
                Section(isPending ? "End Date" : "End Date") {
                    DatePicker(
                        "End",
                        selection: $endDate,
                        in: minEnd...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(.moveRing)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Edit Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let normStart = Calendar.current.startOfDay(for: startDate)
                        let normEnd   = NewChallengeViewModel.endOfDay(endDate)
                        onSave(title, normStart, normEnd)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(canSave ? .moveRing : .secondary)
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Podium (Completed Challenges)

private struct PodiumSection: View {
    let participations: [Participation]
    let userID: String?

    private var top3: [Participation] { Array(participations.prefix(3)) }
    private var rest: [Participation] { Array(participations.dropFirst(3)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "Final Results")
                .padding(.horizontal, 20)

            VStack(spacing: 12) {
                // Podium display — gold/silver/bronze side by side
                if !top3.isEmpty {
                    HStack(alignment: .bottom, spacing: 12) {
                        // Silver (2nd) — left
                        if top3.count > 1 {
                            PodiumPillar(participation: top3[1], rank: 2,
                                         height: 72, isCurrentUser: top3[1].user.id == userID)
                        }
                        // Gold (1st) — center, taller
                        PodiumPillar(participation: top3[0], rank: 1,
                                     height: 96, isCurrentUser: top3[0].user.id == userID)
                        // Bronze (3rd) — right
                        if top3.count > 2 {
                            PodiumPillar(participation: top3[2], rank: 3,
                                         height: 60, isCurrentUser: top3[2].user.id == userID)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // 4th place and beyond
                if !rest.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.cardBackground)
                        VStack(spacing: 0) {
                            ForEach(Array(rest.enumerated()), id: \.element.id) { idx, p in
                                LeaderboardRowView(
                                    participation: p,
                                    isCurrentUser: p.user.id == userID,
                                    showRank: true
                                )
                                if idx < rest.count - 1 {
                                    Divider().padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

private struct PodiumPillar: View {
    let participation: Participation
    let rank: Int
    let height: CGFloat
    let isCurrentUser: Bool

    private var rankColor: Color {
        switch rank {
        case 1: return .rankGold
        case 2: return .rankSilver
        default: return .rankBronze
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Name
            Text(participation.user.displayName)
                .font(.system(size: 11, weight: isCurrentUser ? .bold : .regular))
                .foregroundStyle(isCurrentUser ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Points
            Text("\(Int(participation.totalPoints))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(rankColor)

            // Trophy icon
            Image(systemName: "trophy.fill")
                .font(.system(size: rank == 1 ? 22 : 16))
                .foregroundStyle(rankColor)

            // Pillar
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rankColor.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(rankColor.opacity(isCurrentUser ? 0.5 : 0.2), lineWidth: 1)
                )
                .frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Score History Chart

private struct ScoreHistoryChart: View {
    let participation: Participation
    let challenge: Challenge
    var title: String = "My Points"

    private var scores: [DailyScore] {
        // Bound by the challenge window rather than "today": participants in timezones
        // ahead of the viewer legitimately have a score for the viewer's tomorrow.
        let endDay = Calendar.current.startOfDay(for: challenge.endDate)
        return participation.dailyScores
            .filter { $0.localDayStart() <= endDay }
            .sorted { $0.date < $1.date }
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    /// Half-day before start — pads the left edge so the first dot isn't flush with the axis.
    private var chartStartDate: Date {
        let start = Calendar.current.startOfDay(for: challenge.startDate)
        return start.addingTimeInterval(-43_200) // -12 hours
    }

    /// Half-day after the last day ends — pads the right edge so the last dot has room.
    private var chartEndDate: Date {
        let endDay = Calendar.current.startOfDay(for: challenge.endDate)
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return nextDay.addingTimeInterval(43_200) // +12 hours
    }

    /// Top of the Y axis: round the day's best score up to the next 500 (min 500) so the
    /// line fills the vertical space instead of floating against a fixed 2000 ceiling.
    private var yMax: Double {
        let best = scores.map(\.points).max() ?? 0
        return max(500, (best / 500).rounded(.up) * 500)
    }

    private var yAxisValues: [Double] {
        Array(stride(from: 0, through: yMax, by: 500))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FitnessSectionHeader(title: title)

            Chart(scores, id: \.id) { score in
                let day = score.localDayStart()
                AreaMark(
                    x: .value("Day", day, unit: .day),
                    y: .value("Points", score.points)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.moveRing.opacity(0.35), Color.moveRing.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)
                LineMark(
                    x: .value("Day", day, unit: .day),
                    y: .value("Points", score.points)
                )
                .foregroundStyle(Color.moveRing)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Day", day, unit: .day),
                    y: .value("Points", score.points)
                )
                .foregroundStyle(day == today ? Color.moveRing : Color.moveRing.opacity(0.7))
                .symbolSize(day == today ? 40 : 20)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        // "M/d" → "3/24", "3/25", etc.
                        let label = date.formatted(.dateTime.day())
                        AxisValueLabel(label)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: yAxisValues) { value in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                }
            }
            .chartXScale(domain: chartStartDate...chartEndDate)
            .chartYScale(domain: 0...yMax)
            .frame(height: 100)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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

// MARK: - Previews

#if DEBUG
private enum ChallengeDetailPreviewData {
    static let user = AppUser(id: "u1", displayName: "Sumit", appleUserID: "a1", hasAppleWatch: true)

    static func challenge() -> Challenge {
        let cal = Calendar.current
        return Challenge(
            id: "c1", title: "Summer ☀️", creatorID: "u1",
            startDate: cal.date(byAdding: .day, value: -4, to: Date())!,
            endDate: cal.date(byAdding: .day, value: 2, to: Date())!,
            status: .active, inviteCode: "MC8TEE",
            createdAt: cal.date(byAdding: .day, value: -5, to: Date())!
        )
    }

    static func participation() -> Participation {
        let cal = Calendar.current
        var p = Participation(
            id: "p1", challengeID: "c1", user: user,
            joinedAt: cal.date(byAdding: .day, value: -4, to: Date())!,
            status: .active, hasAppleWatch: true
        )
        p.dailyScores = (0..<5).map { i in
            var ring = RingData(moveRingPct: 1.1, exerciseRingPct: 1.4, standRingPct: 0.9,
                                stepsPct: 0, activeEnergyPct: 0, syncSource: .watch)
            ring.totalSteps = Double(6_000 + i * 1_500)
            ring.distanceMeters = Double(4_000 + i * 1_200)
            return DailyScore(
                id: "s\(i)", participationID: "p1", challengeID: "c1",
                date: cal.date(byAdding: .day, value: -4 + i, to: Date())!,
                points: Double(380 + i * 60), ringData: ring, lastSyncedAt: Date()
            )
        }
        p.totalPoints = p.dailyScores.map(\.points).reduce(0, +)
        p.rank = 2
        return p
    }

    static let standingSecond = ChallengeDetailViewModel.Standing(
        rank: 2, total: 5, points: 2180, pointsBehindLeader: 120, pointsToNextRank: 120)
}

#Preview("Results header") {
    ResultsHeaderCard(standing: ChallengeDetailPreviewData.standingSecond, winnerName: "lucknell")
        .padding()
        .frame(maxHeight: .infinity)
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
}

#Preview("Participant sheet") {
    ParticipantDetailSheet(
        participation: ChallengeDetailPreviewData.participation(),
        challenge: ChallengeDetailPreviewData.challenge(),
        isCurrentUser: true
    )
    .preferredColorScheme(.dark)
}
#endif
