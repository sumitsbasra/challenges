import SwiftUI

// MARK: - Activity Hero Card

/// Designed to match the Apple Fitness "Activity Rings" summary card pixel-for-pixel.
/// Shows the large ring stack on the left, colored metric rows on the right,
/// and a divider footer with today's + total points.
struct MyProgressView: View {
    let participation: Participation

    private var rings: RingData { todayScore?.ringData ?? emptyRingData }

    private var todayScore: DailyScore? {
        participation.dailyScores.last {
            Calendar.current.isDate($0.date, inSameDayAs: Date())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            metricsRow
            Divider()
                .padding(.horizontal, 16)
            stepsDistanceRow
            Divider()
                .padding(.horizontal, 16)
            footer
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
        .padding(.horizontal, 16)
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
        HStack(alignment: .center, spacing: 16) {
            // Rings — leading edge aligned with the card's 16pt padding
            Group {
                // Both paths now show 3 rings:
                // Watch  → Move / Exercise / Stand
                // iPhone → Steps / Exercise / Active Energy (outer→inner)
                ThreeRingView(ringData: rings, size: 130)
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)

            // Metric rows — frame fills remaining width so content spreads to the right edge
            VStack(alignment: .leading, spacing: 10) {
                if participation.hasAppleWatch {
                    MetricRowView(label: "Move",
                                  actual: rings.moveCalories,
                                  goal: rings.moveGoal,
                                  unit: "CAL", color: .moveRing)
                    Divider().opacity(0.2)
                    MetricRowView(label: "Exercise",
                                  actual: rings.exerciseMinutes,
                                  goal: rings.exerciseGoal,
                                  unit: "MIN", color: .exerciseRing)
                    Divider().opacity(0.2)
                    MetricRowView(label: "Stand",
                                  actual: rings.standHours,
                                  goal: rings.standGoal,
                                  unit: "HRS", color: .standRing)
                } else {
                    MetricRowView(label: "Steps",
                                  actual: rings.steps,
                                  goal: rings.stepsGoal,
                                  unit: "STEPS", color: .moveRing)
                    Divider().opacity(0.2)
                    MetricRowView(label: "Exercise",
                                  actual: rings.exerciseMinutes,
                                  goal: rings.exerciseGoal,
                                  unit: "MIN", color: .exerciseRing)
                    Divider().opacity(0.2)
                    MetricRowView(label: "Energy",
                                  actual: rings.activeEnergy,
                                  goal: rings.activeEnergyGoal,
                                  unit: "CAL", color: .standRing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 16)
        }
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
        let locale = Locale.current
        let usesMetric = locale.measurementSystem != .us
        if usesMetric {
            let km = meters / 1000
            return String(format: "%.2f km", km)
        } else {
            let miles = meters / 1609.344
            return String(format: "%.2f mi", miles)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            PointsFooterCell(value: todayScore?.points ?? 0, label: "Today")
                .frame(maxWidth: .infinity)
            Color.fitnessSeparator
                .frame(width: 0.5, height: 30)
            PointsFooterCell(value: participation.totalPoints, label: "Total")
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
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

// MARK: - Metric Row

/// Apple Fitness-style metric row: label on top, "actual/goal UNIT" below.
private struct MetricRowView: View {
    let label:  String
    let actual: Double
    let goal:   Double
    let unit:   String
    let color:  Color

    // Format whole numbers without decimals; keep 1 decimal for fractional values (stand hours)
    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.0f", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(fmt(actual))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text("/\(fmt(goal))")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(color.opacity(0.45))
                Text(" \(unit)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(color.opacity(0.6))
                    .padding(.leading, 2)
            }
            .monospacedDigit()
        }
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

// MARK: - Points Footer

private struct PointsFooterCell: View {
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

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        MyProgressView(participation: Participation(
            id: "p1",
            challengeID: "c1",
            user: AppUser(id: "u1", displayName: "Alex", appleUserID: "a1", hasAppleWatch: true),
            joinedAt: Date(),
            status: .active,
            hasAppleWatch: true,
            dailyScores: [
                DailyScore(id: "s1", participationID: "p1", challengeID: "c1",
                           date: Date(), points: 480,
                           ringData: RingData(moveRingPct: 1.56, exerciseRingPct: 3.1,
                                             standRingPct: 0.83, stepsPct: 0,
                                             activeEnergyPct: 0, syncSource: .watch),
                           lastSyncedAt: Date())
            ],
            totalPoints: 2180,
            rank: 1
        ))
        .padding(.horizontal, 16)
    }
}
