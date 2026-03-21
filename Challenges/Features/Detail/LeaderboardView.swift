import SwiftUI

/// Renders leaderboard rows inside a dark card — no extra padding needed;
/// rows manage their own internal padding.
struct LeaderboardView: View {
    let participations: [Participation]
    let currentUserID: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(participations.enumerated()), id: \.element.id) { idx, p in
                LeaderboardRowView(
                    participation: p,
                    isCurrentUser: p.user.id == currentUserID
                )
                if idx < participations.count - 1 {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }
        }
    }
}
