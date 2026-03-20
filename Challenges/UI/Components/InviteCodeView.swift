import SwiftUI

/// Displays a large, stylized invite code with a copy button.
struct InviteCodeView: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 8) {
            Text("Invite Code")
                .font(.caption.uppercaseSmallCaps())
                .foregroundStyle(Color.secondaryText)

            HStack(spacing: 6) {
                ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .frame(width: 36, height: 44)
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Button {
                UIPasteboard.general.string = code
                withAnimation(.spring(duration: 0.3)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copied = false }
                }
            } label: {
                Label(copied ? "Copied" : "Copy Code",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(copied ? Color.exerciseRing : .accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
