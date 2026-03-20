import SwiftUI

/// Shows the current user's ring progress for today and cumulative points.
struct MyProgressView: View {
    let participation: Participation

    private var todayScore: DailyScore? {
        let today = Calendar.current.startOfDay(for: Date())
        return participation.dailyScores.last {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Ring visualization
            HStack(spacing: 32) {
                if participation.hasAppleWatch {
                    ThreeRingView(ringData: todayScore?.ringData ?? emptyRingData, size: 120)
                } else {
                    TwoRingView(ringData: todayScore?.ringData ?? emptyRingData, size: 120)
                }

                VStack(alignment: .leading, spacing: 8) {
                    PointsBadgeView(points: todayScore?.points ?? 0, label: "Today")
                    PointsBadgeView(points: participation.totalPoints, label: "Total")
                    Text("Rank #\(participation.rank)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(rankColor)
                }
            }

            // Sync source indicator
            if let source = todayScore?.ringData.syncSource {
                HStack(spacing: 4) {
                    Image(systemName: source == .watch ? "applewatch" : "iphone")
                        .font(.caption2)
                    Text("Synced from \(source.rawValue.capitalized)")
                        .font(.caption)
                }
                .foregroundStyle(Color.secondaryText)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var rankColor: Color {
        switch participation.rank {
        case 1: return .rankGold
        case 2: return .rankSilver
        case 3: return .rankBronze
        default: return .primaryText
        }
    }

    private var emptyRingData: RingData {
        RingData(moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                 stepsPct: 0, activeEnergyPct: 0, syncSource: .iphone)
    }
}
