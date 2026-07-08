import SwiftUI
import WidgetKit

struct RankWidgetView: View {
    let entry: RankEntry

    var body: some View {
        if let state = entry.state {
            loadedView(state)
        } else {
            placeholderView
        }
    }

    // MARK: - Loaded State

    private func loadedView(_ state: WidgetState) -> some View {
        let ended = state.daysRemaining <= 0
        return VStack(alignment: .leading, spacing: 4) {
            // Challenge name + icon
            HStack(spacing: 4) {
                Image(systemName: ended ? "flag.checkered" : "trophy.fill")
                    .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.yellow))
                    .font(.caption)
                Text(state.challengeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Rank (large)
            Text("#\(state.rank)")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(ended ? AnyShapeStyle(
                    .secondary) : AnyShapeStyle(Color.white))
                .monospacedDigit()

            // Points
            Text("\(Int(state.totalPoints)) pts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(
                    ended
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(Color(red: 0.573, green: 0.910, blue: 0.165))
                )

            Spacer()

            // Status footer
            if ended {
                Text("Challenge ended")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(state.daysRemaining)d left")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .widgetURL(URL(string: "challenges://challenge/\(state.challengeID)"))
    }

    // MARK: - Placeholder / No Data

    private var placeholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
                .foregroundStyle(Color(red: 0.573, green: 0.910, blue: 0.165))
            Text("No active challenge")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
