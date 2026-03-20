import SwiftUI

/// Animated circular ring that represents one activity ring (move, exercise, or stand).
struct ActivityRingView: View {

    let progress: Double    // 0.0–2.0+ (can exceed 1.0 for the over-achievement segment)
    let color: Color
    let lineWidth: CGFloat

    @State private var animatedProgress: Double = 0

    private var cappedProgress: Double { min(progress, 1.0) }
    private var overProgress: Double   { max(progress - 1.0, 0) }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            // Main arc (0–100%)
            Circle()
                .trim(from: 0, to: min(animatedProgress, 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Over-achievement arc (100–200%), slightly inside
            if animatedProgress > 1.0 {
                Circle()
                    .trim(from: 0, to: min(animatedProgress - 1.0, 1.0))
                    .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth * 0.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth * 0.2)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.6)) {
                animatedProgress = newValue
            }
        }
    }
}

/// Stacked three-ring view for Watch users.
struct ThreeRingView: View {
    let ringData: RingData
    let size: CGFloat

    private let lineWidthRatio: CGFloat = 0.1

    var body: some View {
        ZStack {
            ActivityRingView(progress: ringData.moveRingPct,     color: .moveRing,
                             lineWidth: size * lineWidthRatio)

            ActivityRingView(progress: ringData.exerciseRingPct, color: .exerciseRing,
                             lineWidth: size * lineWidthRatio)
                .padding(size * lineWidthRatio * 1.6)

            ActivityRingView(progress: ringData.standRingPct,    color: .standRing,
                             lineWidth: size * lineWidthRatio)
                .padding(size * lineWidthRatio * 3.2)
        }
        .frame(width: size, height: size)
    }
}

/// Two-ring view for non-Watch users (steps + active energy).
struct TwoRingView: View {
    let ringData: RingData
    let size: CGFloat

    private let lineWidthRatio: CGFloat = 0.12

    var body: some View {
        ZStack {
            ActivityRingView(progress: ringData.stepsPct,        color: .stepsColor,
                             lineWidth: size * lineWidthRatio)

            ActivityRingView(progress: ringData.activeEnergyPct, color: .activeEnergyColor,
                             lineWidth: size * lineWidthRatio)
                .padding(size * lineWidthRatio * 1.8)
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 24) {
        ThreeRingView(ringData: RingData(
            moveRingPct: 0.85, exerciseRingPct: 1.2, standRingPct: 0.6,
            stepsPct: 0, activeEnergyPct: 0, syncSource: .watch
        ), size: 100)

        TwoRingView(ringData: RingData(
            moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
            stepsPct: 0.9, activeEnergyPct: 1.4, syncSource: .iphone
        ), size: 100)
    }
    .padding()
}
