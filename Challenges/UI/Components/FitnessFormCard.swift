import SwiftUI

/// Reusable dark card container used inside form-style sheets (New Challenge, Join).
struct FitnessFormCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
