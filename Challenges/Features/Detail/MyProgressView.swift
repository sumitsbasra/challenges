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
        HStack(alignment: .center, spacing: 18) {
            // Rings
            Group {
                if participation.hasAppleWatch {
                    ThreeRingView(ringData: rings, size: 130)
                } else {
                    TwoRingView(ringData: rings, size: 130)
                }
            }
            .padding(.leading, 14)
            .padding(.vertical, 14)

            // Metric rows
            VStack(alignment: .leading, spacing: 12) {
                if participation.hasAppleWatch {
                    MetricRowView(label: "Move",
                                  pct: rings.moveRingPct,
                                  unit: "CAL", color: .moveRing)
                    MetricRowView(label: "Exercise",
                                  pct: rings.exerciseRingPct,
                                  unit: "MIN", color: .exerciseRing)
                    MetricRowView(label: "Stand",
                                  pct: rings.standRingPct,
                                  unit: "HRS", color: .standRing)
                } else {
                    MetricRowView(label: "Steps",
                                  pct: rings.stepsPct,
                                  unit: "STEPS", color: .stepsColor)
                    MetricRowView(label: "Energy",
                                  pct: rings.activeEnergyPct,
                                  unit: "CAL", color: .activeEnergyColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 16)
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

/// Single ring metric displayed exactly like Apple Fitness:
/// colored dot · label · large colored completion percentage + unit
private struct MetricRowView: View {
    let label: String
    let pct: Double       // 0.0–2.0
    let unit: String
    let color: Color

    private var completionPct: Int { Int(pct * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Label row with colored dot
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }

            // Value row: "156%" in ring color, small unit beside it
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(completionPct)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text("%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color.opacity(0.75))
                    .padding(.leading, 1)
                Text(unit)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(color.opacity(0.65))
            }
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
