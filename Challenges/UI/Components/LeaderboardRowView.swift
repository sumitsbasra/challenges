import SwiftUI

struct LeaderboardRowView: View {
    let participation: Participation
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            RankBadgeView(rank: participation.rank)
                .frame(width: 32, height: 32)

            // Avatar placeholder
            Circle()
                .fill(avatarColor)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(participation.user.displayName.prefix(1))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }

            // Name + device indicator
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(participation.user.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isCurrentUser ? Color.moveRing : Color.primaryText)
                    Image(systemName: participation.hasAppleWatch ? "applewatch" : "iphone")
                        .font(.caption2)
                        .foregroundStyle(Color.secondaryText)
                }
                if let todayScore = participation.dailyScores.last {
                    Text("+\(Int(todayScore.points)) pts today")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                }
            }

            Spacer()

            // Total points
            Text("\(Int(participation.totalPoints))")
                .font(.pointsMedium())
                .foregroundStyle(Color.primaryText)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(isCurrentUser ? Color.moveRing.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        let index = abs(participation.user.id.hashValue) % colors.count
        return colors[index]
    }
}
