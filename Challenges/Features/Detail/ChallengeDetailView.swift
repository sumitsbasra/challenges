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
    @State private var reactionTarget: Participation?
    /// Row currently showing the tapback bar (long-press).
    @State private var reactionOverlayTarget: Participation?
    /// Leaderboard row frames in the "challengePage" space, for anchoring the tapback bar.
    @State private var rowFrames: [String: CGRect] = [:]

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
        .coordinateSpace(name: "challengePage")
        .onPreferenceChange(RowFrameKey.self) { rowFrames = $0 }
        .overlay { reactionTapbackOverlay }
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
        // No opaque toolbar background: it forces a hard edge under the nav bar and
        // defeats iOS 26's progressive scroll-edge blur (Settings-style).
        .softTopScrollEdge()
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
                    // Manual escape hatch for stale data. The page has no pull-to-refresh:
                    // a refreshable action leaks into every presented sheet through the
                    // (read-only) environment, breaking the cards' swipe-to-dismiss.
                    // Auto-sync on open/foreground/push covers the normal cases.
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

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
                isCurrentUser: p.user.id == session.userID
            )
        }
        .sheet(item: $reactionTarget) { p in
            ReactionPickerSheet(recipient: p, vm: vm)
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

    // MARK: - Reaction tapback overlay

    /// iMessage-style tapback: dim the page, lift the pressed row, float a material
    /// capsule of reactions above it.
    @ViewBuilder
    private var reactionTapbackOverlay: some View {
        if let p = reactionOverlayTarget, let frame = rowFrames[p.id] {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.black.opacity(0.45))
                    .ignoresSafeArea()
                    .onTapGesture { dismissReactionOverlay() }

                // Lifted copy of the pressed row.
                LeaderboardRowView(
                    participation: p,
                    isCurrentUser: false,
                    showRank: true,
                    reactionEmojis: vm.todaysReactionsByParticipation[p.id] ?? []
                )
                .frame(width: frame.width, height: frame.height)
                .background(Color.cardInset)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                .position(x: frame.midX, y: frame.midY)

                ReactionTapbackBar(
                    sentEmoji: vm.myReactionToday(to: p.id),
                    onSelect: { emoji in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await vm.sendReaction(emoji, to: p) }
                        dismissReactionOverlay()
                    },
                    onMore: {
                        dismissReactionOverlay()
                        reactionTarget = p
                    }
                )
                .offset(x: max(12, frame.minX + 8),
                        // Above the row; below it when the row sits too close to the top.
                        y: frame.minY < 130 ? frame.maxY + 10 : frame.minY - 66)
                .transition(.scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity))
            }
            .transition(.opacity)
        }
    }

    private func dismissReactionOverlay() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            reactionOverlayTarget = nil
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
                            // Tap a participant for their score breakdown; long-press to
                            // react with the custom tapback bar (active challenges,
                            // other participants only). The avatar badge teaches the hold.
                            if challenge.status != .pending {
                                row
                                    .contentShape(Rectangle())
                                    .background(GeometryReader { geo in
                                        Color.clear.preference(
                                            key: RowFrameKey.self,
                                            value: [p.id: geo.frame(in: .named("challengePage"))]
                                        )
                                    })
                                    .onTapGesture { selectedParticipant = p }
                                    .onLongPressGesture(minimumDuration: 0.3) {
                                        guard challenge.status == .active, !isMe,
                                              vm.currentUserParticipation != nil else { return }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                                            reactionOverlayTarget = p
                                        }
                                    }
                                    // The row stopped being a Button when the tapback
                                    // gesture arrived; restore its button semantics and
                                    // give VoiceOver a path to reactions, since a custom
                                    // long-press overlay is invisible to it.
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("Shows their stats.")
                                    .accessibilityActions {
                                        if challenge.status == .active, !isMe,
                                           vm.currentUserParticipation != nil {
                                            ForEach(Reaction.allowedEmojis, id: \.self) { emoji in
                                                Button("React \(emoji)") {
                                                    Task { await vm.sendReaction(emoji, to: p) }
                                                }
                                            }
                                            Button("More reactions") { reactionTarget = p }
                                        }
                                    }
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

// MARK: - Reaction Picker Sheet

extension View {
    /// iOS 26's progressive blur under the navigation bar (the Settings look) instead
    /// of a hard edge; earlier OS versions keep the standard system material bar.
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}

/// Frames of the leaderboard rows in the "challengePage" coordinate space, used to
/// anchor the reaction tapback overlay to the pressed row.
private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The floating capsule of quick reactions shown over a long-pressed leaderboard row.
struct ReactionTapbackBar: View {
    let sentEmoji: String?
    let onSelect: (String) -> Void
    let onMore: () -> Void

    /// Quick three, plus the already-sent emoji when it came from the full picker.
    private var emojis: [String] {
        var list = Reaction.allowedEmojis
        if let sentEmoji, !list.contains(sentEmoji) {
            list.append(sentEmoji)
        }
        return list
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                // Liquid Glass, matching the system chrome around it.
                barContent.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                barContent.background(.regularMaterial, in: Capsule())
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
    }

    private var barContent: some View {
        HStack(spacing: 2) {
            ForEach(emojis, id: \.self) { emoji in
                Button { onSelect(emoji) } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(width: 44, height: 44)
                        .background {
                            if sentEmoji == emoji {
                                Circle().fill(Color.exerciseRing.opacity(0.28))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sentEmoji == emoji ? "\(emoji) sent" : "Send \(emoji)")
            }

            Button(action: onMore) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.09)))
                    // 44pt minimum hit target (HIG) around the 36pt visual.
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More reactions")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

/// The full emoji grid behind the tapback bar's "+" button.
private struct ReactionPickerSheet: View {
    let recipient: Participation
    let vm: ChallengeDetailViewModel
    @Environment(\.dismiss) private var dismiss

    private var sentEmoji: String? { vm.myReactionToday(to: recipient.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("React to \(recipient.user.displayName)")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                ForEach(Reaction.allowedEmojis + Reaction.extendedEmojis, id: \.self) { emoji in
                    let isSelected = sentEmoji == emoji
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await vm.sendReaction(emoji, to: recipient) }
                        dismiss()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 24))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isSelected ? Color.exerciseRing.opacity(0.18) : Color.cardInset,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(isSelected ? Color.exerciseRing : .clear, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSelected ? "\(emoji) sent" : "Send \(emoji)")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Participant Detail Sheet

/// Tapping a leaderboard row opens this — a participant's rank, total, score history,
/// and daily breakdown. Reuses the same chart/breakdown components as the hero card.
struct ParticipantDetailSheet: View {
    let participation: Participation
    let challenge: Challenge
    let isCurrentUser: Bool
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
        // Maps-style card: grab handle instead of a nav bar and Done button, opens at
        // medium height and drags up — an overlay, not a new page. Swipe down to dismiss.
        ScrollView {
            VStack(spacing: 20) {
                header
                    .padding(.top, 8)

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
                }

                if !workouts.isEmpty {
                    workoutsSection
                }
            }
            .padding(16)
        }
        .background(Color.appBackground.ignoresSafeArea())
        // Single detent: one downward swipe dismisses instead of parking at half height.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task { await loadWorkouts() }
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
                Text(name)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
            .softTopScrollEdge()
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

/// Apple Health-style daily points chart: bars in a scrollable 7-day window covering the
/// full challenge, tap or drag to select a day and see its points in a callout.
struct ScoreHistoryChart: View {
    let participation: Participation
    let challenge: Challenge
    var title: String = "My Points"

    /// Raw (continuous) selection from the chart gesture; snapped to a day for display.
    @State private var rawSelection: Date?
    /// Measured size of the floating callout, for edge clamping and the connector line.
    @State private var calloutSize: CGSize = .zero

    init(participation: Participation, challenge: Challenge, title: String = "My Points",
         initialSelection: Date? = nil) {
        self.participation = participation
        self.challenge = challenge
        self.title = title
        _rawSelection = State(initialValue: initialSelection)
    }

    private var cal: Calendar { Calendar.current }
    private var startDay: Date { cal.startOfDay(for: challenge.startDate) }
    private var endDay: Date { cal.startOfDay(for: challenge.endDate) }

    /// Best score per local calendar day (duplicate records can't inflate a bar),
    /// clamped to the 600 daily cap so a stray over-cap record can't overshoot the
    /// axis. Bound by the challenge window rather than "today": participants in
    /// timezones ahead of the viewer legitimately have a score for the viewer's tomorrow.
    private var entries: [(day: Date, points: Double)] {
        var best: [Date: Double] = [:]
        for score in participation.dailyScores {
            let day = score.localDayStart()
            guard day >= startDay, day <= endDay else { continue }
            best[day] = min(600, max(best[day] ?? 0, score.points))
        }
        return best.map { ($0.key, $0.value) }.sorted { $0.day < $1.day }
    }

    private var dayCount: Int {
        (cal.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
    }

    /// End of the axis: the slot after the final day so its bar has room.
    private var domainEnd: Date {
        cal.date(byAdding: .day, value: 1, to: endDay) ?? endDay
    }

    /// Land on the most recent 7 days with data rather than the challenge start.
    private var initialScrollDate: Date {
        let anchor = min(cal.startOfDay(for: Date()), endDay)
        let windowStart = cal.date(byAdding: .day, value: -6, to: anchor) ?? anchor
        return max(startDay, windowStart)
    }

    private var selectedEntry: (day: Date, points: Double)? {
        guard let rawSelection else { return nil }
        let day = cal.startOfDay(for: rawSelection)
        return entries.first { $0.day == day }
    }

    /// Fixed top of the Y axis: 600 is the daily cap, so a maxed day always reaches
    /// the top gridline and the scale reads the same on every challenge.
    private let yMax: Double = 600

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FitnessSectionHeader(title: title)

            Chart {
                ForEach(entries, id: \.day) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Points", entry.points)
                    )
                    .foregroundStyle(barColor(for: entry.day))
                    .cornerRadius(3)
                }
            }
            // The callout is drawn manually in an overlay rather than as a mark
            // annotation: Charts' annotation overflow clamps against the FULL
            // scrollable content, not the visible window, so edge-of-viewport bars
            // still clipped — and a RuleMark can't know the callout's pixel height,
            // so its guide line always ran to the top of the plot instead of
            // stopping at the card. Health's pattern, done by hand: card pinned
            // inside the visible plot (sliding at the edges), connector line from
            // the card's bottom edge down to the bar top, staying on the bar even
            // when the card has slid.
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let sel = selectedEntry, let plotAnchor = proxy.plotFrame {
                        let plot = geo[plotAnchor]
                        let barCenter = sel.day.addingTimeInterval(43_200)
                        if let xInPlot = proxy.position(forX: barCenter),
                           xInPlot > -30, xInPlot < plot.width + 30 {
                            let xBar = plot.minX + xInPlot
                            let halfWidth = max(calloutSize.width, 80) / 2
                            let calloutX = min(max(xBar, plot.minX + halfWidth + 2),
                                               plot.maxX - halfWidth - 2)
                            let calloutHeight = max(calloutSize.height, 44)
                            let calloutTop = plot.minY + 2

                            if let yInPlot = proxy.position(forY: sel.points) {
                                let barTop = plot.minY + yInPlot
                                let lineTop = calloutTop + calloutHeight + 2
                                if barTop > lineTop {
                                    Path { p in
                                        p.move(to: CGPoint(x: xBar, y: lineTop))
                                        p.addLine(to: CGPoint(x: xBar, y: barTop))
                                    }
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                                }
                            }

                            selectionCallout(sel)
                                .background(GeometryReader { g in
                                    Color.clear
                                        .onAppear { calloutSize = g.size }
                                        .onChange(of: g.size) { _, new in calloutSize = new }
                                })
                                .position(x: calloutX, y: calloutTop + calloutHeight / 2)
                        }
                    }
                }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: Double(min(7, dayCount)) * 86_400)
            .chartScrollPosition(initialX: initialScrollDate)
            .chartXSelection(value: $rawSelection)
            .chartXScale(domain: startDay...domainEnd)
            .chartYScale(domain: 0...yMax)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        // Weekday labels like Apple Health's weekly view; the selection
                        // callout carries the exact date. The explicit standard anchor
                        // avoids Charts' "custom UnitPoint not supported" runtime warning
                        // that `centered` alone triggers.
                        AxisValueLabel(centered: true, anchor: .top) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: 0, through: yMax, by: 300))) { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                }
            }
            .frame(height: 170)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// When a day is selected, keep it vivid and dim the rest so the focus reads clearly.
    private func barColor(for day: Date) -> Color {
        guard let sel = selectedEntry else { return .moveRing }
        return day == sel.day ? .moveRing : Color.moveRing.opacity(0.35)
    }

    private func selectionCallout(_ entry: (day: Date, points: Double)) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(Int(entry.points)) pts")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(entry.day, format: .dateTime.month(.abbreviated).day())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.cardInset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    /// Long challenge for exercising the scrollable chart: 24 days, 18 elapsed,
    /// varied scores with a couple of zero-days (no record) mixed in.
    static func marathonChallenge() -> Challenge {
        let cal = Calendar.current
        return Challenge(
            id: "c2", title: "Road to NYC", creatorID: "u1",
            startDate: cal.date(byAdding: .day, value: -17, to: Date())!,
            endDate: cal.date(byAdding: .day, value: 6, to: Date())!,
            status: .active, inviteCode: "FX4K9R",
            createdAt: cal.date(byAdding: .day, value: -18, to: Date())!
        )
    }

    static func marathonParticipation() -> Participation {
        let cal = Calendar.current
        var p = Participation(
            id: "p2", challengeID: "c2", user: user,
            joinedAt: cal.date(byAdding: .day, value: -17, to: Date())!,
            status: .active, hasAppleWatch: true
        )
        let pointsByDay: [Double] = [420, 600, 380, 0, 510, 600, 455, 300, 600,
                                     580, 0, 490, 600, 350, 600, 525, 440, 600]
        p.dailyScores = pointsByDay.enumerated().compactMap { i, pts in
            guard pts > 0 else { return nil }   // rest days: no record at all
            let day = cal.date(byAdding: .day, value: -17 + i, to: Date())!
            let ring = RingData(moveRingPct: 1, exerciseRingPct: 1, standRingPct: 1,
                                stepsPct: 0, activeEnergyPct: 0, syncSource: .watch)
            return DailyScore(id: "m\(i)", participationID: "p2", challengeID: "c2",
                              date: DailyScore.noonUTC(for: day), points: pts,
                              ringData: ring, lastSyncedAt: day)
        }
        return p
    }
}

#Preview("Points chart") {
    ScoreHistoryChart(participation: ChallengeDetailPreviewData.marathonParticipation(),
                      challenge: ChallengeDetailPreviewData.marathonChallenge())
        .padding()
        .frame(maxHeight: .infinity)
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
}

#Preview("Results header") {
    ResultsHeaderCard(standing: ChallengeDetailPreviewData.standingSecond, winnerName: "lucknell")
        .padding()
        .frame(maxHeight: .infinity)
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
}

#Preview("Participant sheet") {
    // Presented as a real sheet so the grab handle and medium detent show.
    Color.appBackground
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ParticipantDetailSheet(
                participation: ChallengeDetailPreviewData.participation(),
                challenge: ChallengeDetailPreviewData.challenge(),
                isCurrentUser: true
            )
        }
        .preferredColorScheme(.dark)
}

#Preview("Reaction picker") {
    let challenge = ChallengeDetailPreviewData.challenge()
    let vm = ChallengeDetailViewModel(challenge: challenge)
    return Color.appBackground
        .sheet(isPresented: .constant(true)) {
            ReactionPickerSheet(recipient: ChallengeDetailPreviewData.participation(), vm: vm)
        }
        .preferredColorScheme(.dark)
}
#endif
