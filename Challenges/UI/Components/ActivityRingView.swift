import SwiftUI
import UIKit

private extension Color {
    /// The vivid leading-edge shade for the lengthwise gradient (base color at the tail →
    /// this at the tip). Like Apple, the tip is brighter and shifts hue slightly toward
    /// magenta/warm (Move red → pink, Exercise green → lighter), staying saturated.
    var ringLeadingShade: Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var hue = h - 0.03
        if hue < 0 { hue += 1 }
        return Color(hue: Double(hue),
                     saturation: Double(max(0, s - 0.05)),
                     brightness: Double(min(1, b + 0.23)),
                     opacity: Double(a))
    }

    /// Linear RGB blend toward `other` by `fraction` (0…1).
    func blended(to other: Color, fraction: Double) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = CGFloat(min(max(fraction, 0), 1))
        return Color(red: Double(r1 + (r2 - r1) * f),
                     green: Double(g1 + (g2 - g1) * f),
                     blue: Double(b1 + (b2 - b1) * f))
    }
}

// MARK: - Single Ring

/// Animated circular activity ring.
/// Matches Apple Fitness: solid vibrant color, and when a ring exceeds 100% the second
/// lap stacks on top of the first with a soft shadow cast by its leading tip.
struct ActivityRingView: View {

    let progress: Double   // 0.0 – 2.0+ (values above 1.0 draw a second lap)
    let color: Color
    let lineWidth: CGFloat

    @State private var animatedProgress: Double = 0

    var body: some View {
        GeometryReader { geo in
            RingArcs(progress: animatedProgress, color: color, lineWidth: lineWidth, size: geo.size)
                .frame(width: geo.size.width, height: geo.size.height)
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
}

/// Pure, `Animatable` rendering of one ring's arcs at a given progress.
///
/// Conforming to `Animatable` (rather than reading `progress` as a plain computed
/// property elsewhere) makes SwiftUI re-run this `body` at every interpolated frame
/// of the enclosing `withAnimation` transaction, not just once at the start and once
/// at the end. That matters here because `.trim(from:to:)` animates smoothly on its
/// own, but `AngularGradient` does not — its color stops snap straight to whatever
/// the latest state produces. Before this split, the gradient (and therefore the
/// bright "tip" color and the second-lap tip/shadow, all derived from the same
/// `animatedProgress`) jumped to its FINAL configuration immediately while only the
/// trimmed arc length grew — so the ring's end-state tip color was visible from
/// frame one, with the fill just growing to reveal it. Driving everything through
/// one Animatable value keeps trim, gradients, and tip position in lockstep.
private struct RingArcs: View, Animatable {
    var progress: Double
    let color: Color
    let lineWidth: CGFloat
    let size: CGSize

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var capped: Double { min(progress, 1.0) }

    /// Whole laps stacked beneath the partial top lap once the ring passes 100%.
    private var lapsBelow: Double {
        guard progress >= 1.0 else { return 0 }
        return max(1, progress.rounded(.down))
    }

    /// The top lap's arc: the FRACTIONAL part of progress, so the tip keeps moving at
    /// 200%, 300%, … instead of parking at 12 o'clock (where its shadow hides under the
    /// lap and the ring reads as a flat donut). A small minimum overlap keeps the
    /// 12 o'clock join covered right at whole-lap boundaries.
    private var over: Double {
        guard progress >= 1.0 else { return 0 }
        let fraction = progress.truncatingRemainder(dividingBy: 1.0)
        return min(max(fraction, 0.04), 0.9999)
    }

    /// Shade at the 12 o'clock wrap where the top lap begins — the deeper into the laps,
    /// the closer to the bright leading shade, so each lap boundary hands off seamlessly
    /// while the true tip stays brightest.
    private var wrapShade: Color {
        // >= 1: at exactly 100% the wrap must be the leading shade, otherwise the base
        // renders flat and the tip pops in as a bright dot against it.
        guard progress >= 1 else { return color }
        return color.blended(to: color.ringLeadingShade, fraction: lapsBelow / progress)
    }

    /// Start shade of the topmost FULL lap drawn beneath the partial lap. Matching the
    /// lap-by-lap shades means crossing a whole-lap boundary mid-animation repaints the
    /// base with exactly the colors the finishing lap already showed — no pop.
    private var underStartShade: Color {
        guard progress >= 1 else { return color }
        return color.blended(to: color.ringLeadingShade, fraction: (lapsBelow - 1) / progress)
    }

    /// Base fill (tail → wrap). Under 100% it runs tail color to the bright leading
    /// shade; once lapped it shows the topmost full lap's gradient beneath the tip lap.
    private var firstLapGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [over > 0 ? underStartShade : color,
                                        over > 0 ? wrapShade : color.ringLeadingShade]),
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360 * max(capped, 0.0001))
        )
    }

    /// Second-lap fill (wrap → bright tip), continuing the first lap's gradient so the
    /// 12 o'clock join is seamless. Spans only the drawn arc.
    private var secondLapGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [wrapShade, color.ringLeadingShade]),
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360 * max(over, 0.0001))
        )
    }

    var body: some View {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        ZStack {
            // Dim track.
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)

            // First lap.
            Circle()
                .trim(from: 0, to: capped)
                .stroke(firstLapGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Second lap (over 100%), stacked on top.
            if over > 0 {
                // The first lap's angular gradient wraps hard at 12 o'clock (base
                // shade meets wrapShade), and the second lap's antialiased start edge
                // lets a hairline of that dark wrap bleed through. A short solid arc
                // in the shared wrap shade straddles 12 o'clock beneath the seam so
                // both sides of the butt edge sit on identical paint.
                Circle()
                    .trim(from: 0, to: 0.016)
                    .stroke(wrapShade, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90 - 0.008 * 360))

                // Soft shadow just AHEAD of the leading tip (along the direction of
                // travel), drawn BENEATH the second lap. "Ahead" is always the exposed
                // first-lap surface the second lap hasn't reached yet, so the shadow is
                // visible for every tip position — a fixed downward offset would slip
                // under the lap when the tip is on the left. It's a dark blur, not a
                // bright shape, so nothing reads as a circle, and the start stays clean.
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: lineWidth * 0.9, height: lineWidth * 0.9)
                    .blur(radius: lineWidth * 0.14)
                    .position(tipPoint(for: over, center: center, radius: radius,
                                       ahead: lineWidth * 0.28))

                // Butt start cap: a round cap would protrude half a line-width
                // BACKWARDS past 12 o'clock onto the exposed first lap, and its curved
                // silhouette shows against the tip shadow once the tip gets close to
                // the start (progress near 200%). A butt edge lands exactly on the
                // 12 o'clock join, where both laps are the same shade — invisible.
                Circle()
                    .trim(from: 0, to: over)
                    .stroke(secondLapGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))

                // Rounded leading tip, restored as a dot over the butt end.
                Circle()
                    .fill(color.ringLeadingShade)
                    .frame(width: lineWidth, height: lineWidth)
                    .position(tipPoint(for: over, center: center, radius: radius, ahead: 0))
            }

            // Cross-width sheen: a whisper of convex shading so the band reads as a
            // gently rounded tube without dulling the color. No inner-edge darkening
            // (keeps colors vivid edge-to-edge); just a soft center highlight and a
            // faint outer edge. Both laps share the radius, so one overlay covers
            // whichever is on top; trimmed to the drawn arc so the track stays flat.
            Circle()
                .trim(from: 0, to: capped)
                .stroke(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear,               location: 0.0),
                            .init(color: .white.opacity(0.06), location: 0.6),   // barely-there center highlight
                            .init(color: .black.opacity(0.04), location: 1.0),   // whisper of an outer edge
                        ]),
                        center: .center,
                        startRadius: radius - lineWidth / 2,
                        endRadius: radius + lineWidth / 2
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    /// The leading tip position, optionally nudged `ahead` points along the clockwise
    /// direction of travel (used to place the tip shadow on the exposed first-lap surface
    /// the second lap hasn't reached yet; `ahead: 0` is the tip itself).
    private func tipPoint(for fraction: Double, center: CGPoint, radius: CGFloat, ahead: CGFloat) -> CGPoint {
        let angle = (-90 + fraction * 360) * .pi / 180
        let tip = CGPoint(x: center.x + radius * cos(angle),
                          y: center.y + radius * sin(angle))
        // Clockwise tangent (direction of travel) in screen space (y points down).
        let tangent = (dx: -sin(angle), dy: cos(angle))
        return CGPoint(x: tip.x + ahead * tangent.dx,
                       y: tip.y + ahead * tangent.dy)
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
        VStack(spacing: 32) {
            // Over-100% on all three rings — shows the stacked second lap + tip shadow.
            ThreeRingView(ringData: RingData(
                moveRingPct: 1.45, exerciseRingPct: 1.7, standRingPct: 1.25,
                stepsPct: 0, activeEnergyPct: 0, syncSource: .watch
            ), size: 150)

            // Mixed: under, over, partial.
            ThreeRingView(ringData: RingData(
                moveRingPct: 0.6, exerciseRingPct: 1.35, standRingPct: 0.9,
                stepsPct: 0, activeEnergyPct: 0, syncSource: .watch
            ), size: 150)
        }
    }
}
