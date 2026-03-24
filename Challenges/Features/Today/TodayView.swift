import SwiftUI
import HealthKit

// MARK: - Data Model

struct TodayItem: Identifiable, Codable {
    let id: String                  // challenge.id
    let challenge: Challenge
    let rank: Int
    let participantCount: Int
    let todayPoints: Double
    let totalPoints: Double

    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: challenge.endDate).day ?? 0)
    }

    var daysRemainingText: String {
        let cal = Calendar.current
        if cal.isDateInToday(challenge.endDate)                       { return "Ends today" }
        if cal.isDateInTomorrow(challenge.endDate)                    { return "Ends tomorrow" }
        if cal.isDateInToday(challenge.startDate)                     { return "Starts today" }
        return "Ongoing"
    }
}

// MARK: - ViewModel

@Observable
final class TodayViewModel {

    // Rings
    var ringData: RingData = RingData(
        moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
        stepsPct: 0, activeEnergyPct: 0, syncSource: .iphone
    )
    var steps: Double = 0
    var activeEnergy: Double = 0
    var exerciseMinutes: Double = 0
    var isLoadingRings = true

    // Challenges
    var activeItems: [TodayItem] = []
    var isLoadingChallenges = true

    var hasWatch: Bool = UserDefaults.standard.bool(forKey: "hasAppleWatch")

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

        // Re-detect Watch on every load — fixes stale flags set during
        // onboarding before HealthKit permissions were granted.
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
            steps       = s
            activeEnergy = e

            // GoalResolver is @MainActor; we're already on main actor here.
            let goalResolver  = GoalResolver()
            let stepsGoal     = goalResolver.stepsGoal
            let energyGoal    = goalResolver.activeEnergyGoal
            ringData = RingData(
                moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                stepsPct:        stepsGoal  > 0 ? s / stepsGoal  : 0,
                activeEnergyPct: energyGoal > 0 ? e / energyGoal : 0,
                syncSource: .iphone
            )
        }
    }

    // MARK: - Challenges

    @MainActor
    func loadChallenges(userID: String) async {
        isLoadingChallenges = true
        defer { isLoadingChallenges = false }

        do {
            let all    = try await ck.fetchChallenges(forUserID: userID)
            let active = all.filter { $0.status == .active }

            var items: [TodayItem] = []
            for challenge in active {
                var parts  = try await ck.fetchParticipations(challengeID: challenge.id)
                let scores = try await ck.fetchDailyScores(challengeID: challenge.id)

                for i in parts.indices {
                    parts[i].dailyScores = scores
                        .filter  { $0.participationID == parts[i].id }
                        .sorted  { $0.date < $1.date }
                }

                let ranked = ScoreAggregator.ranked(parts)
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
            activeItems = items
        } catch {
            // Non-fatal — Challenges tab shows the full list regardless.
            #if DEBUG
            print("[TodayVM] Failed to load challenges: \(error)")
            #endif
        }
    }
}

// MARK: - Today View

struct TodayView: View {
    @Environment(UserSession.self) private var session
    @State private var vm = TodayViewModel()

    private var dateTitle: String {
        Date().formatted(.dateTime.weekday(.wide).month().day())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        // Activity rings hero
                        ringsCard
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // Active challenge standings
                        if vm.isLoadingChallenges || !vm.activeItems.isEmpty {
                            challengesSection
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .navigationDestination(for: Challenge.self) { challenge in
                ChallengeDetailView(challenge: challenge)
            }
            .task {
                guard let userID = session.userID else { return }
                await vm.load(userID: userID)
            }
            .refreshable {
                guard let userID = session.userID else { return }
                await vm.load(userID: userID)
            }
        }
    }

    // MARK: - Rings Card

    private var ringsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity")
                    .font(.fitnessHeader())
                    .foregroundStyle(.primary)
                Spacer()
                if vm.isLoadingRings {
                    ProgressView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(alignment: .center, spacing: 18) {
                Group {
                    if vm.hasWatch {
                        ThreeRingView(ringData: vm.ringData, size: 130)
                    } else {
                        TwoRingView(ringData: vm.ringData, size: 130)
                    }
                }
                .padding(.leading, 14)
                .padding(.vertical, 14)

                VStack(alignment: .leading, spacing: 12) {
                    if vm.hasWatch {
                        TodayMetricRow(label: "Move",     pct: vm.ringData.moveRingPct,
                                       value: vm.activeEnergy,    unit: "CAL", color: .moveRing)
                        TodayMetricRow(label: "Exercise", pct: vm.ringData.exerciseRingPct,
                                       value: vm.exerciseMinutes, unit: "MIN", color: .exerciseRing)
                        TodayMetricRow(label: "Stand",    pct: vm.ringData.standRingPct,
                                       value: nil,                unit: "HRS", color: .standRing)
                    } else {
                        TodayMetricRow(label: "Steps",  pct: vm.ringData.stepsPct,
                                       value: vm.steps,        unit: "STEPS", color: .stepsColor)
                        TodayMetricRow(label: "Energy", pct: vm.ringData.activeEnergyPct,
                                       value: vm.activeEnergy, unit: "CAL",   color: .activeEnergyColor)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Challenges Section

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FitnessSectionHeader(title: "Active Challenges")
                .padding(.horizontal, 20)

            if vm.isLoadingChallenges && vm.activeItems.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.activeItems) { item in
                        NavigationLink(value: item.challenge) {
                            TodayChallengeCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Today Challenge Card

private struct TodayChallengeCard: View {
    let item: TodayItem

    var body: some View {
        HStack(spacing: 14) {
            rankBadge

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
                    Text("\(item.daysRemaining)d left")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Int(item.totalPoints).formatted())
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("pts total")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rankBadge: some View {
        ZStack {
            Circle()
                .fill(rankColor.opacity(0.15))
                .frame(width: 44, height: 44)
            Text("#\(item.rank)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(rankColor)
        }
    }

    private var rankColor: Color {
        switch item.rank {
        case 1:  return .rankGold
        case 2:  return .rankSilver
        case 3:  return .rankBronze
        default: return .secondaryText
        }
    }
}

// MARK: - Metric Row

/// Compact ring metric row: colored dot · label · large % value · raw value
private struct TodayMetricRow: View {
    let label: String
    let pct: Double        // 0.0 – 2.0
    let value: Double?     // raw value (calories, steps, etc.) — nil hides it
    let unit: String
    let color: Color

    private var completionPct: Int { Int(pct * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(completionPct)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text("%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color.opacity(0.75))
                if let value {
                    Text(Int(value).formatted())
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(color.opacity(0.65))
                    Text(unit)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(color.opacity(0.5))
                }
            }
        }
    }
}
