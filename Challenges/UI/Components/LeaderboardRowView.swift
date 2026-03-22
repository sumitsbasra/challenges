import SwiftUI

// MARK: - Leaderboard Row

/// A single leaderboard entry styled after Apple Fitness's Sharing tab.
/// Rank · Avatar · Name + device icon | Points (right-aligned, large)
struct LeaderboardRowView: View {
    let participation: Participation
    let isCurrentUser: Bool
    var showRank: Bool = true

    private var displayName: String { participation.user.displayName }
    private var todayPts: Double {
        participation.dailyScores
            .filter { Calendar.current.isDate($0.date, inSameDayAs: Date()) }
            .reduce(0) { $0 + $1.points }
    }

    var body: some View {
        HStack(spacing: 14) {
            if showRank { rankView }
            avatarView
            nameStack
            Spacer(minLength: 8)
            pointsStack
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 16)
        .background(Color.clear)
    }

    // MARK: - Rank

    private var rankView: some View {
        Group {
            switch participation.rank {
            case 1:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankGold)
            case 2:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankSilver)
            case 3:
                Image(systemName: "trophy.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.rankBronze)
            default:
                Text("#\(participation.rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 30, height: 30)
    }

    // MARK: - Avatar

    private var avatarView: some View {
        Circle()
            .fill(avatarGradient)
            .frame(width: 40, height: 40)
            .overlay {
                if isCurrentUser,
                   let data = UserDefaults.standard.data(forKey: "profilePhotoData"),
                   let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Text(displayName.prefix(1).uppercased())
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(isCurrentUser ? Color.white.opacity(0.35) : Color.clear,
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
                    .foregroundStyle(.primary)
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


