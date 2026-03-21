import SwiftUI

// MARK: - Leaderboard Row

/// A single leaderboard entry styled after Apple Fitness's Sharing tab.
/// Rank · Avatar · Name + device icon | Points (right-aligned, large)
struct LeaderboardRowView: View {
    let participation: Participation
    let isCurrentUser: Bool

    private var displayName: String { participation.user.displayName }
    private var todayPts: Double {
        participation.dailyScores
            .filter { Calendar.current.isDate($0.date, inSameDayAs: Date()) }
            .reduce(0) { $0 + $1.points }
    }

    var body: some View {
        HStack(spacing: 14) {
            rankView
            avatarView
            nameStack
            Spacer(minLength: 8)
            pointsStack
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .background(
            isCurrentUser
                ? Color.moveRing.opacity(0.07)
                : Color.clear
        )
    }

    // MARK: - Rank

    private var rankView: some View {
        ZStack {
            Circle()
                .fill(rankFillColor)
                .frame(width: 30, height: 30)
            Text(rankText)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(rankTextColor)
        }
    }

    private var rankText: String {
        switch participation.rank {
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        default: return "\(participation.rank)"
        }
    }

    private var rankFillColor: Color {
        switch participation.rank {
        case 1: return .rankGold
        case 2: return Color(white: 0.30)
        case 3: return Color(red: 0.35, green: 0.20, blue: 0.08)
        default: return Color(white: 0.18)
        }
    }

    private var rankTextColor: Color {
        switch participation.rank {
        case 1: return .black
        case 2: return .rankSilver
        case 3: return .rankBronze
        default: return Color(white: 0.60)
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Circle()
            .fill(avatarGradient)
            .frame(width: 40, height: 40)
            .overlay {
                Text(displayName.prefix(1).uppercased())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(
                Circle()
                    .strokeBorder(isCurrentUser ? Color.moveRing.opacity(0.6) : Color.clear,
                                  lineWidth: 2)
            )
    }

    private var avatarGradient: LinearGradient {
        let palette: [(Color, Color)] = [
            (.blue, Color(red: 0.0, green: 0.5, blue: 1.0)),
            (.green, Color(red: 0.0, green: 0.8, blue: 0.4)),
            (.orange, Color(red: 1.0, green: 0.4, blue: 0.0)),
            (.purple, Color(red: 0.6, green: 0.0, blue: 1.0)),
            (Color(red: 1.0, green: 0.2, blue: 0.5), .pink),
            (.teal, Color(red: 0.0, green: 0.8, blue: 0.8)),
        ]
        let pair = palette[abs(participation.user.id.hashValue) % palette.count]
        return LinearGradient(colors: [pair.0, pair.1],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Name

    private var nameStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrentUser ? Color.moveRing : .primary)
                    .lineLimit(1)
                Image(systemName: participation.hasAppleWatch ? "applewatch" : "iphone")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if todayPts > 0 {
                Text("+\(Int(todayPts).formatted()) today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Points

    private var pointsStack: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(Int(participation.totalPoints).formatted())
                .font(.leaderboardPoints())
                .foregroundStyle(.primary)
            Text("pts")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Points Badge (reusable)

struct RankBadgeView: View {
    let rank: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(badgeColor)
            Text("\(rank)")
                .font(.rankBadge())
                .foregroundStyle(rank <= 3 ? Color.black : Color.white)
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
            Text(Int(points).formatted())
                .font(.pointsMedium())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
