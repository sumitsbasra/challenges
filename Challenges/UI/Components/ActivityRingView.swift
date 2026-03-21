import SwiftUI

// MARK: - Single Ring

/// Animated circular activity ring with AngularGradient fill and tip glow.
/// Matches Apple Fitness ring visual fidelity: vibrant color, depth gradient, soft tip glow.
struct ActivityRingView: View {

    let progress: Double   // 0.0 – 2.0+ (values above 1.0 draw a second inner arc)
    let color: Color
    let lineWidth: CGFloat

    @State private var animatedProgress: Double = 0

    private var capped: Double { min(animatedProgress, 1.0) }
    private var over:   Double { max(animatedProgress - 1.0, 0) }

    var body: some View {
        ZStack {
            trackRing
            if capped > 0 {
                mainArc
                tipGlow(at: capped, inset: 0)
            }
            if over > 0 {
                overArc
                tipGlow(at: over, inset: lineWidth * 0.175)
            }
        }
        .onAppear {
            withAnimation(.interpolatingSpring(stiffness: 42, damping: 10).delay(0.05)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.75, dampingFraction: 0.82)) {
                animatedProgress = newValue
            }
        }
    }

    // MARK: - Sub-views

    /// Dim track behind the filled arc
    private var trackRing: some View {
        Circle()
            .stroke(color.opacity(0.13), lineWidth: lineWidth)
    }

    /// Main arc with angular gradient for depth (darker at start, full color at tip)
    private var mainArc: some View {
        Circle()
            .trim(from: 0, to: capped)
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: color.opacity(0.80), location: 0.0),
                        .init(color: color,               location: 0.9),
                        .init(color: color,               location: 1.0),
                    ],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(capped * 360 - 90)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }

    /// Second-lap arc (100–200%) drawn at slightly smaller radius with 75% opacity
    private var overArc: some View {
        let inset = lineWidth * 0.175
        return Circle()
            .trim(from: 0, to: over)
            .stroke(
                color.opacity(0.80),
                style: StrokeStyle(lineWidth: lineWidth * 0.72, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .padding(inset)
    }

    /// Soft radial glow at the leading tip of the arc — creates Apple's signature 3-D lift
    @ViewBuilder
    private func tipGlow(at tipProgress: Double, inset: CGFloat) -> some View {
        let span = 0.028
        Circle()
            .trim(from: max(0, tipProgress - span), to: tipProgress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth * 1.7, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(inset)
            .blur(radius: lineWidth * 0.55)
            .opacity(0.55)
            .allowsHitTesting(false)
    }
}

// MARK: - Three-Ring Stack (Apple Watch)

/// Concentric three-ring view for Apple Watch users.
/// Order matches Apple Fitness: Move (outer), Exercise (middle), Stand (inner).
struct ThreeRingView: View {
    let ringData: RingData
    let size: CGFloat

    var body: some View {
        let lw  = size * 0.096   // ring line width
        let gap = lw * 1.72      // gap between rings

        ZStack {
            ActivityRingView(progress: ringData.moveRingPct,
                             color: .moveRing, lineWidth: lw)

            ActivityRingView(progress: ringData.exerciseRingPct,
                             color: .exerciseRing, lineWidth: lw)
                .padding(gap)

            ActivityRingView(progress: ringData.standRingPct,
                             color: .standRing, lineWidth: lw)
                .padding(gap * 2)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Two-Ring Stack (iPhone only)

/// Concentric two-ring view for non-Apple Watch users (steps + active energy).
struct TwoRingView: View {
    let ringData: RingData
    let size: CGFloat

    var body: some View {
        let lw  = size * 0.115
        let gap = lw * 1.80

        ZStack {
            ActivityRingView(progress: ringData.stepsPct,
                             color: .stepsColor, lineWidth: lw)

            ActivityRingView(progress: ringData.activeEnergyPct,
                             color: .activeEnergyColor, lineWidth: lw)
                .padding(gap)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview("Rings") {
    ZStack {
        Color.black.ignoresSafeArea()
        HStack(spacing: 32) {
            ThreeRingView(ringData: RingData(
                moveRingPct: 1.56, exerciseRingPct: 3.1, standRingPct: 0.83,
                stepsPct: 0, activeEnergyPct: 0, syncSource: .watch
            ), size: 120)

            TwoRingView(ringData: RingData(
                moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                stepsPct: 0.72, activeEnergyPct: 1.2, syncSource: .iphone
            ), size: 120)
        }
    }
}
