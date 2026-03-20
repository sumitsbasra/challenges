import SwiftUI

struct LeaderboardView: View {
    let participations: [Participation]
    let currentUserID: String

    var body: some View {
        LazyVStack(spacing: 4) {
            ForEach(participations) { participation in
                LeaderboardRowView(
                    participation: participation,
                    isCurrentUser: participation.user.id == currentUserID
                )
            }
        }
        .padding(.horizontal)
    }
}
