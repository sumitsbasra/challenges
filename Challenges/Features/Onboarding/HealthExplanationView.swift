import SwiftUI

/// Pre-authorization explanation screen — required by App Store guidelines.
/// Explains exactly why each data type is needed before the system permission sheet appears.
struct HealthExplanationView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Hero icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.moveRing.opacity(0.28), Color.moveRing.opacity(0.05)],
                                center: .center, startRadius: 20, endRadius: 70
                            )
                        )
                        .frame(width: 120, height: 120)

                    // Mini ring stack as decoration
                    ThreeRingView(
                        ringData: RingData(
                            moveRingPct: 0.85, exerciseRingPct: 1.0, standRingPct: 0.70,
                            stepsPct: 0, activeEnergyPct: 0, syncSource: .watch
                        ),
                        size: 72
                    )
                }
                .padding(.bottom, 28)

                // Title
                Text("Activity Access")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)

                // Body
                Text("Challenges reads your Apple Health data to calculate your competition score. Your data is used only on your device and never shared with other participants.")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.bottom, 40)

                // Data access list
                VStack(spacing: 0) {
                    DataRow(icon: "figure.run",    color: .moveRing,
                            title: "Active Energy",
                            detail: "Calories burned while active — the Move ring.")
                    Divider().padding(.horizontal, 16)
                    DataRow(icon: "timer",          color: .exerciseRing,
                            title: "Exercise Minutes",
                            detail: "Brisk activity credited by Apple Watch.")
                    Divider().padding(.horizontal, 16)
                    DataRow(icon: "figure.stand",   color: .standRing,
                            title: "Stand Hours",
                            detail: "Hours you stood at least one minute (Watch only).")
                    Divider().padding(.horizontal, 16)
                    DataRow(icon: "shoeprints.fill", color: .stepsColor,
                            title: "Step Count",
                            detail: "Total daily steps — used instead of Stand for iPhone users.")
                }
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)

                Spacer()

                // CTA
                Button(action: onContinue) {
                    Text("Allow Activity Access")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Color.moveRing)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)

                Text("You can change these permissions any time in Settings.")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.40))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.bottom, 48)
            }
        }
    }
}

private struct DataRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
