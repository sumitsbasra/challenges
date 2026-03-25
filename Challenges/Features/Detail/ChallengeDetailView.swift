import SwiftUI
import Intents
import Charts

struct ChallengeDetailView: View {
    let challenge: Challenge
    @Environment(UserSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ChallengeDetailViewModel
    @State private var showDeleteConfirm  = false
    @State private var showLeaveConfirm   = false
    @State private var showEditChallenge  = false

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

                // 3. Score history chart — active challenges with data
                if challenge.status == .active,
                   let me = vm.currentUserParticipation,
                   !me.dailyScores.isEmpty {
                    ScoreHistoryChart(participation: me, challenge: challenge)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                }

                // 4. Results/Leaderboard — hidden until challenge starts
                if challenge.status == .completed {
                    PodiumSection(participations: vm.rankedParticipations, userID: session.userID)
                        .padding(.top, 28)
                } else if challenge.status == .active {
                    leaderboardSection
                        .padding(.top, 28)
                }

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
                        Button {
                            showEditChallenge = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) {
                            showLeaveConfirm = true
                        } label: {
                            Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
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
            FitnessSectionHeader(title: "Leaderboard")
                .padding(.horizontal, 20)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.cardBackground)

                if vm.isLoading && vm.participations.isEmpty {
                    ProgressView()
                        .padding(32)
                } else if vm.rankedParticipations.isEmpty {
                    VStack(spacing: 6) {
                        Text(challenge.status == .active ? "No participants yet." : "Waiting for participants.")
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
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
    }
    private var minEnd: Date {
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: startDate)!)
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

    private var scores: [DailyScore] {
        participation.dailyScores.sorted { $0.date < $1.date }
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "My Points")

            Chart(scores, id: \.id) { score in
                let day = Calendar.current.startOfDay(for: score.date)
                BarMark(
                    x: .value("Day", day, unit: .day),
                    y: .value("Points", score.points)
                )
                .foregroundStyle(
                    day == today
                        ? Color.moveRing
                        : Color.moveRing.opacity(0.45)
                )
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        let label = date.formatted(.dateTime.day())
                        AxisValueLabel(label)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                }
            }
            .chartXScale(domain: challenge.startDate...challenge.endDate)
            .frame(height: 100)
        }
        .padding(16)
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
