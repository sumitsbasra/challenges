import SwiftUI

/// Compact invite-code display matching the create-challenge screen style.
/// Shows "INVITE CODE" label, monospaced code text, and a copy button — all in one row.
struct InviteCodeView: View {
    let code: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("INVITE CODE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Text(code)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Button {
                UIPasteboard.general.string = code
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copied = false }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                    Text(copied ? "Copied" : "Copy")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(copied ? .exerciseRing : .moveRing)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background((copied ? Color.exerciseRing : Color.moveRing).opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
