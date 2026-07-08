import SwiftUI

// MARK: - Activity Hero Card

/// Designed to match the Apple Fitness "Activity Rings" summary card pixel-for-pixel.
/// Shows the large ring stack on the left and colored metric rows on the right.
struct MyProgressView: View {
    let participation: Participation

    // Use the live UserDefaults value — the same source the scoring engine uses.
    // participation.hasAppleWatch is stamped at join time and can be stale
    // (e.g. user paired a Watch after joining the challenge).
    @AppStorage("hasAppleWatch")   private var hasAppleWatch   = false
    @AppStorage("preferredUnits")  private var preferredUnits  = "Imperial"

    private var rings: RingData { todayScore?.ringData ?? emptyRingData }

    private var todayScore: DailyScore? {
        participation.dailyScores
            .filter(\.isForToday)
            .max { $0.points < $1.points }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            metricsRow
            Divider()
                .padding(.horizontal, 20)
            stepsDistanceRow
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Today's Activity")
                .font(.fitnessHeader())
                .foregroundStyle(.primary)
            Spacer()
            rankPill
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var rankPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .black))
            Text(rankLabel)
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .foregroundStyle(rankColor)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(rankColor.opacity(0.14))
        .clipShape(Capsule())
    }

    // MARK: - Rings + metrics

    private var metricsRow: some View {
        // Matches the home screen "Activity" card exactly: same ring view, same metric
        // rows, same spacing — Watch shows Move/Exercise/Stand, iPhone shows
        // Steps/Exercise/Energy with the dedicated iPhone ring colors.
        HStack(alignment: .center, spacing: 28) {
            Group {
                if hasAppleWatch {
                    ThreeRingView(ringData: rings, size: 132)
                } else {
                    IPhoneRingView(ringData: rings, size: 132)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if hasAppleWatch {
                    HomeMetricRow(label: "Move",     current: rings.moveCalories,    goal: rings.moveGoal,         unit: "cal", color: .moveRing)
                    HomeMetricRow(label: "Exercise", current: rings.exerciseMinutes, goal: rings.exerciseGoal,     unit: "min", color: .exerciseRing)
                    HomeMetricRow(label: "Stand",    current: rings.standHours,      goal: rings.standGoal,        unit: "hrs", color: .standRing)
                } else {
                    HomeMetricRow(label: "Steps",    current: rings.steps,           goal: rings.stepsGoal,        unit: "steps", color: .stepsColor)
                    HomeMetricRow(label: "Exercise", current: rings.exerciseMinutes, goal: rings.exerciseGoal,     unit: "min",   color: .exerciseRing)
                    HomeMetricRow(label: "Energy",   current: rings.activeEnergy,    goal: rings.activeEnergyGoal, unit: "cal",   color: .activeEnergyColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Steps + Distance

    private var stepsDistanceRow: some View {
        HStack(spacing: 0) {
            StatCell(
                label: "Steps",
                value: rings.totalSteps.formatted(.number.grouping(.automatic).precision(.fractionLength(0)))
            )
            .frame(maxWidth: .infinity)
            Color.fitnessSeparator
                .frame(width: 0.5, height: 28)
            StatCell(
                label: "Distance",
                value: distanceString
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
    }

    private var distanceString: String {
        let meters = rings.distanceMeters
        // Respect the explicit preference the user set in Profile → Units.
        // Fall back to locale when no preference has been saved yet.
        let usesMetric: Bool
        if UserDefaults.standard.object(forKey: "preferredUnits") != nil {
            usesMetric = preferredUnits == "Metric"
        } else {
            usesMetric = Locale.current.measurementSystem != .us
        }
        if usesMetric {
            let km = meters / 1000
            return String(format: "%.2f km", km)
        } else {
            let miles = meters / 1609.344
            return String(format: "%.2f mi", miles)
        }
    }

    // MARK: - Helpers

    private var rankLabel: String {
        switch participation.rank {
        case 1: return "#1"
        case 2: return "#2"
        case 3: return "#3"
        default: return "#\(participation.rank)"
        }
    }

    private var rankColor: Color {
        switch participation.rank {
        case 1: return .rankGold
        case 2: return .rankSilver
        case 3: return .rankBronze
        default: return .secondaryText
        }
    }

    private var emptyRingData: RingData {
        RingData(moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                 stepsPct: 0, activeEnergyPct: 0, syncSource: .iphone)
    }
}

// MARK: - Stat Cell (steps / distance)

private struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Points Card

/// Standalone card shown below the activity rings card with today's and total points.
struct PointsCardView: View {
    let participation: Participation

    private var todayPoints: Double {
        participation.dailyScores
            .filter(\.isForToday)
            .map(\.points)
            .max() ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            PointsCell(value: todayPoints, label: "Today")
                .frame(maxWidth: .infinity)
            Color.fitnessSeparator
                .frame(width: 0.5, height: 30)
            PointsCell(value: participation.totalPoints, label: "Total")
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PointsCell: View {
    let value: Double
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(Int(value).formatted())
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text("\(label) pts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

private func previewParticipation(watch: Bool) -> Participation {
    var ring = RingData(
        moveRingPct: 0.74, exerciseRingPct: 1.4, standRingPct: 0.83,
        stepsPct: 0.82, activeEnergyPct: 0.84, syncSource: watch ? .watch : .iphone
    )
    ring.moveCalories = 520; ring.moveGoal = 700
    ring.exerciseMinutes = 42; ring.exerciseGoal = 30
    ring.standHours = 10; ring.standGoal = 12
    ring.steps = 8_240; ring.stepsGoal = 10_000
    ring.activeEnergy = 420; ring.activeEnergyGoal = 500
    ring.totalSteps = 8_240; ring.distanceMeters = 5_400
    return Participation(
        id: "p1", challengeID: "c1",
        user: AppUser(id: "u1", displayName: "Alex", appleUserID: "a1", hasAppleWatch: watch),
        joinedAt: Date(), status: .active, hasAppleWatch: watch,
        dailyScores: [DailyScore(id: "s1", participationID: "p1", challengeID: "c1",
                                 date: Date(), points: 480, ringData: ring, lastSyncedAt: Date())],
        totalPoints: 2180, rank: 1
    )
}

#Preview("My Progress — Watch") {
    UserDefaults.standard.set(true, forKey: "hasAppleWatch")
    return ZStack {
        Color.appBackground.ignoresSafeArea()
        MyProgressView(participation: previewParticipation(watch: true))
            .padding(.horizontal, 16)
    }
    .preferredColorScheme(.dark)
}

#Preview("My Progress — iPhone") {
    UserDefaults.standard.set(false, forKey: "hasAppleWatch")
    return ZStack {
        Color.appBackground.ignoresSafeArea()
        MyProgressView(participation: previewParticipation(watch: false))
            .padding(.horizontal, 16)
    }
    .preferredColorScheme(.dark)
}
