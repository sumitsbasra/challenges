import SwiftUI

struct RankBadgeView: View {
    let rank: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor)
            Text("\(rank)")
                .font(.rankBadge())
                .foregroundStyle(rank <= 3 ? .black : .white)
        }
    }

    private var badgeColor: Color {
        switch rank {
        case 1: return .rankGold
        case 2: return .rankSilver
        case 3: return .rankBronze
        default: return Color(.systemGray4)
        }
    }
}

struct PointsBadgeView: View {
    let points: Double
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(points))")
                .font(.pointsMedium())
                .foregroundStyle(Color.primaryText)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.secondaryText)
        }
    }
}
