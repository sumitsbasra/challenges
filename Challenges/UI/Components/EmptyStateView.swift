import SwiftUI

/// Apple Fitness-style empty state: large SF symbol with a gradient tint,
/// bold title, descriptive caption, and optional CTA button.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with ring gradient tint
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.moveRing.opacity(0.18), Color.exerciseRing.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.moveRing)
            }
            .padding(.bottom, 24)

            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 28)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .frame(minWidth: 200)
                        .background(Color.moveRing)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
