import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .foregroundStyle(Color.secondaryText)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .padding(32)
    }
}

#Preview {
    EmptyStateView(
        systemImage: "trophy",
        title: "No active challenges",
        message: "Start one with friends and see who can close their rings the most.",
        actionTitle: "New Challenge",
        action: {}
    )
}
