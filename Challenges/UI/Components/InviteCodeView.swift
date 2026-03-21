import SwiftUI

/// Displays a 6-character invite code with individual letter tiles and a copy button.
/// Styled after the Apple Fitness sharing aesthetics — dark tiles, ring-colored letters.
struct InviteCodeView: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            Text("INVITE CODE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            // Letter tiles
            HStack(spacing: 7) {
                ForEach(Array(code.enumerated()), id: \.offset) { idx, char in
                    LetterTile(character: char, colorIndex: idx)
                }
            }

            // Copy button
            Button {
                UIPasteboard.general.string = code
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    copied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copied = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                    Text(copied ? "Copied!" : "Copy Code")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(copied ? .exerciseRing : .moveRing)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background((copied ? Color.exerciseRing : Color.moveRing).opacity(0.14))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

private struct LetterTile: View {
    let character: Character
    let colorIndex: Int

    // Cycle through ring colors across the 6 tiles
    private var tileColor: Color {
        let palette: [Color] = [.moveRing, .moveRing, .exerciseRing, .exerciseRing, .standRing, .standRing]
        return palette[colorIndex % palette.count]
    }

    var body: some View {
        Text(String(character))
            .font(.system(size: 26, weight: .bold, design: .monospaced))
            .foregroundStyle(tileColor)
            .frame(width: 42, height: 50)
            .background(tileColor.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tileColor.opacity(0.22), lineWidth: 1)
            )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        InviteCodeView(code: "FX4K9R")
            .padding(24)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding()
    }
}
