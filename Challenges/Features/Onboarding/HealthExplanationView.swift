import SwiftUI

/// Shown before requesting HealthKit permissions. App Store review requires
/// a contextual explanation of why each data type is needed.
struct HealthExplanationView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon cluster
            ZStack {
                Circle()
                    .fill(Color.moveRing.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: "heart.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.moveRing)
            }
            .padding(.bottom, 32)

            Text("Activity Access")
                .font(.largeTitle.bold())
                .padding(.bottom, 12)

            Text("Challenges reads your Activity rings to calculate your competition score. Your data is used only to compute points — it is never shared with other participants or stored outside Apple's servers.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.secondaryText)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)

            // What we access
            VStack(alignment: .leading, spacing: 16) {
                DataRowView(icon: "figure.run", color: .moveRing,
                            title: "Move (Active Energy)",
                            detail: "Tracks how many calories you burn while active.")
                DataRowView(icon: "timer", color: .exerciseRing,
                            title: "Exercise Minutes",
                            detail: "Minutes of brisk activity credited by Apple Watch.")
                DataRowView(icon: "figure.stand", color: .standRing,
                            title: "Stand Hours",
                            detail: "Hours you stood for at least one minute (Watch only).")
                DataRowView(icon: "shoeprints.fill", color: .stepsColor,
                            title: "Steps",
                            detail: "Total step count (used instead of stand for iPhone users).")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)

            Spacer()

            Button("Continue") { onContinue() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}

private struct DataRowView: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Color.secondaryText)
            }
        }
    }
}
