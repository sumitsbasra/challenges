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
            if capped > 0 { mainArc }
            if over > 0 {
                overShadowArc  // dark blurred arc — edges bleed beyond overArc stroke
                overArc        // solid color arc covers shadow center
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

    /// Dim track behind the arc.
    private var trackRing: some View {
        Circle()
            .stroke(color.opacity(0.18), lineWidth: lineWidth)
    }

    /// Main arc: solid color, rounded ends.
    private var mainArc: some View {
        Circle()
            .trim(from: 0, to: capped)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }

    /// Shadow only near the tip of the overArc (last 10% of the arc).
    /// Keeps shadow away from 12 o'clock for partial arcs, while for 200%
    /// it covers the region just before 12 o'clock where it bleeds visibly.
    private var overShadowArc: some View {
        let clamped = min(over, 0.9999)
        let shadowStart = max(clamped - 0.10, 0)
        return Circle()
            .trim(from: shadowStart, to: clamped)
            .stroke(Color.black.opacity(0.5),
                    style: StrokeStyle(lineWidth: lineWidth * 1.6, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .blur(radius: lineWidth * 0.5)
    }

    /// Overlap arc: solid color, rounded ends, on top of the shadow arc.
    private var overArc: some View {
        Circle()
            .trim(from: 0, to: min(over, 0.9999))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

// MARK: - Three-Ring Stack (Apple Watch)

/// Concentric three-ring view for Apple Watch users.
/// Order matches Apple Fitness: Move (outer), Exercise (middle), Stand (inner).
struct ThreeRingView: View {
    let ringData: RingData
    let size: CGFloat

    var body: some View {
        let lw  = size * 0.115   // ring line width
        let gap = lw * 1.3       // gap between rings

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

// MARK: - Three-Ring Stack (iPhone only)

/// Concentric three-ring view for non-Apple Watch users.
/// Order mirrors the scoring metrics: Steps (outer), Exercise (middle), Energy (inner).
struct IPhoneRingView: View {
    let ringData: RingData
    let size: CGFloat

    var body: some View {
        let lw  = size * 0.115   // matches ThreeRingView so both cards look consistent
        let gap = lw * 1.3

        ZStack {
            ActivityRingView(progress: ringData.stepsPct,
                             color: .stepsColor, lineWidth: lw)

            ActivityRingView(progress: ringData.exerciseRingPct,
                             color: .exerciseRing, lineWidth: lw)
                .padding(gap)

            ActivityRingView(progress: ringData.activeEnergyPct,
                             color: .activeEnergyColor, lineWidth: lw)
                .padding(gap * 2)
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

            IPhoneRingView(ringData: RingData(
                moveRingPct: 0, exerciseRingPct: 0.9, standRingPct: 0,
                stepsPct: 0.72, activeEnergyPct: 1.2, syncSource: .iphone
            ), size: 120)
        }
    }
}
