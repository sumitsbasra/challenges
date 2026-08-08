import SwiftUI

// MARK: - Results Header Card Mockups (Apple Fitness design language)
//
// Five explorations for the "final place" card on the completed challenge
// screen, staying strictly inside the Fitness visual system: flat card
// surfaces on true black, no gradients, SF Rounded bold numerals in vivid
// accent colors, gray caption labels, hairline separators.
// Preview-only — nothing here is wired into the app.

private struct MockResult {
    let rank: Int
    let total: Int
    let points: Double
    let marginOverNext: Double   // pts ahead of the runner-up (0 if not 1st)
    let challengeName: String
    let othersBeaten: [String]   // display names ranked below the viewer
    var podiumNames: [String] = []  // first names in rank order, "You" included

    var isWinner: Bool { rank == 1 }

    var isPodium: Bool { rank <= 3 }

    var medalColor: Color {
        switch rank {
        case 1: return .rankGold
        // Brighter than .rankSilver so silver reads as a shiny medal, not
        // the same gray as an off-podium finish.
        case 2: return Color(white: 0.88)
        case 3: return .rankBronze
        default: return .secondaryText
        }
    }
}

private let sampleWin = MockResult(
    rank: 1, total: 3, points: 12650, marginOverNext: 7746,
    challengeName: "July 🔥", othersBeaten: ["Emily Maples", "Maria L"],
    podiumNames: ["You", "Emily", "Maria"]
)
private let sampleLoss = MockResult(
    rank: 2, total: 3, points: 4904, marginOverNext: 0,
    challengeName: "July 🔥", othersBeaten: ["Maria L"],
    podiumNames: ["Emily", "You", "Maria"]
)

// MARK: - Option 1: Big Number
//
// The Fitness "Move" treatment: a quiet gray caps label, one huge rounded
// numeral in the accent color, and nothing else competing with it.

private struct BigNumberCard: View {
    let result: MockResult

    var body: some View {
        VStack(spacing: 4) {
            Text("FINAL PLACE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            Text(rankOrdinal(result.rank))
                .font(.system(size: 56, weight: .black, design: .rounded))
                .foregroundStyle(result.medalColor)

            Text(result.isWinner ? "You won • \(result.total) participants"
                                 : "of \(result.total) participants")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Option 1 Iterations
//
// Variations on the Big Number card, each borrowing a different numeric
// treatment from Fitness.

/// 1B — Value/unit split: the digit huge, the ordinal suffix smaller at the
/// baseline, the way Fitness sets "512 CAL".
private struct BigNumberSplitCard: View {
    let result: MockResult

    private var suffix: String {
        rankOrdinal(result.rank).filter(\.isLetter)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("FINAL PLACE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(result.rank)")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                Text(suffix.uppercased())
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(result.medalColor)

            Text(result.isWinner ? "You won • \(result.total) participants"
                                 : "of \(result.total) participants")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// 1C — Activity card layout: left-aligned white label over the colored
/// value, medal on the trailing edge, like the Move/Exercise/Stand rows.
private struct BigNumberActivityCard: View {
    let result: MockResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Final Place")
                    .font(.system(size: 15, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(rankOrdinal(result.rank))
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(result.medalColor)
                    Text("of \(result.total)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(result.isWinner ? "You won" : "Challenge complete")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(rankMedal(result.rank))
                .font(.system(size: 44))
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// 1D — Rank + points pair: the ordinal stays the hero, with the final
/// score as a second colored value, like a two-metric Fitness stack.
private struct BigNumberPointsCard: View {
    let result: MockResult

    var body: some View {
        VStack(spacing: 6) {
            Text("FINAL PLACE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            Text(rankOrdinal(result.rank))
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(result.medalColor)

            Text("\(Int(result.points).formatted()) pts")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.exerciseRing)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// 1E — Fraction: rank over field size in one line, the way Fitness sets
/// "512/500" on the Move row.
private struct BigNumberFractionCard: View {
    let result: MockResult

    var body: some View {
        VStack(spacing: 2) {
            Text("FINAL PLACE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(rankOrdinal(result.rank))
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(result.medalColor)
                Text("/\(result.total)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(result.isWinner ? "You won" : "Challenge complete")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Podium Medallion Iterations
//
// Variations on the round-one Podium Medallion: a circular medal with the
// rank numeral inside, on a flat card. Each iteration changes the medal
// treatment or the layout around it.

/// The medal itself, reused across iterations. Angular gradient ring with a
/// tinted center and the rank numeral.
private struct MedallionView: View {
    let result: MockResult
    var diameter: CGFloat = 84
    var glow: Bool = true

    var body: some View {
        ZStack {
            if result.isPodium {
                // Metallic ring + tinted center — only medals get the shine.
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                result.medalColor,
                                result.medalColor.opacity(0.45),
                                .white.opacity(0.9),
                                result.medalColor,
                            ],
                            center: .center
                        ),
                        lineWidth: diameter * 0.06
                    )
                Circle()
                    .fill(result.medalColor.opacity(0.15))
                    .padding(diameter * 0.06)
            } else {
                // Off-podium: a plain hairline ring, deliberately not a medal.
                Circle()
                    .strokeBorder(Color.fitnessSeparator, lineWidth: 1.5)
            }
            Text(rankOrdinal(result.rank))
                .font(.system(size: diameter * 0.31, weight: .black, design: .rounded))
                .foregroundStyle(result.isPodium ? result.medalColor : .secondaryText)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: glow && result.isPodium ? result.medalColor.opacity(0.35) : .clear,
                radius: 12)
    }
}

/// PM-A — Baseline: the round-one card as pasted.
private struct PodiumMedallionCard: View {
    let result: MockResult

    var body: some View {
        VStack(spacing: 14) {
            MedallionView(result: result)

            VStack(spacing: 4) {
                Text(result.isWinner ? "You won \(result.challengeName)" : "\(result.challengeName) complete")
                    .font(.title3.weight(.bold))
                Text("Out of \(result.total) participants")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// PM-B — Laurels: SF Symbol laurel branches flanking the medal, the way
/// Fitness awards frame their badges.
private struct MedallionLaurelsCard: View {
    let result: MockResult

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "laurel.leading")
                    .font(.system(size: 44, weight: .light))
                MedallionView(result: result, diameter: 76)
                Image(systemName: "laurel.trailing")
                    .font(.system(size: 44, weight: .light))
            }
            .foregroundStyle(result.medalColor)

            VStack(spacing: 4) {
                Text(result.isWinner ? "You won \(result.challengeName)" : "\(result.challengeName) complete")
                    .font(.title3.weight(.bold))
                Text("Out of \(result.total) participants")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// PM-C — Ribbon: the medal hangs from a V-ribbon in the ring colors,
/// like a physical race medal.
private struct MedallionRibbonCard: View {
    let result: MockResult

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                // Two angled ribbon straps meeting behind the medal.
                HStack(spacing: 26) {
                    ribbonStrap.rotationEffect(.degrees(24))
                    ribbonStrap.rotationEffect(.degrees(-24))
                }
                .offset(y: -2)

                MedallionView(result: result, diameter: 78, glow: false)
                    .offset(y: 30)
            }
            .frame(height: 112)

            VStack(spacing: 4) {
                Text(result.isWinner ? "You won \(result.challengeName)" : "\(result.challengeName) complete")
                    .font(.title3.weight(.bold))
                Text("Out of \(result.total) participants")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// One strap of the ribbon: move-red edges around a white core.
    private var ribbonStrap: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Color.moveRing)
            Rectangle().fill(.white.opacity(0.9))
            Rectangle().fill(Color.moveRing)
        }
        .frame(width: 18, height: 54)
    }
}

/// PM-D — Compact row: the medal shrinks and moves left, text stacks
/// beside it. Half the height of the baseline.
private struct MedallionRowCard: View {
    let result: MockResult

    var body: some View {
        HStack(spacing: 16) {
            MedallionView(result: result, diameter: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.isWinner ? "You won \(result.challengeName)" : "\(result.challengeName) complete")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(rankOrdinal(result.rank)) of \(result.total) • \(Int(result.points).formatted()) pts")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// PM-E — With points: baseline layout, but the subtitle becomes a colored
/// points line with the winning margin.
private struct MedallionPointsCard: View {
    let result: MockResult

    var body: some View {
        VStack(spacing: 14) {
            MedallionView(result: result)

            VStack(spacing: 4) {
                Text(result.isWinner ? "You won \(result.challengeName)" : "\(result.challengeName) complete")
                    .font(.title3.weight(.bold))

                HStack(spacing: 5) {
                    Text("\(Int(result.points).formatted()) pts")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.exerciseRing)
                    if result.isWinner, result.marginOverNext > 0 {
                        Text("• +\(Int(result.marginOverNext).formatted()) ahead")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("• \(rankOrdinal(result.rank)) of \(result.total)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Fresh Iterations (dense layouts, no floating badge)

/// FR-A — Podium Chart: the whole podium drawn as three bars filling the
/// card width, with your column lit in the medal color.
private struct PodiumChartCard: View {
    let result: MockResult

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                podiumColumn(rank: 2, barHeight: 52)
                podiumColumn(rank: 1, barHeight: 78)
                podiumColumn(rank: 3, barHeight: 38)
            }

            Text(result.isWinner
                 ? "You won \(result.challengeName) • \(Int(result.points).formatted()) pts"
                 : "You finished \(rankOrdinal(result.rank)) of \(result.total) • \(Int(result.points).formatted()) pts")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func name(forRank rank: Int) -> String? {
        let idx = rank - 1
        return result.podiumNames.indices.contains(idx) ? result.podiumNames[idx] : nil
    }

    private func podiumColumn(rank: Int, barHeight: CGFloat) -> some View {
        let name = name(forRank: rank)
        let isYou = name == "You"
        let tint: Color = isYou ? result.medalColor : .cardInset

        return VStack(spacing: 6) {
            if let name {
                Text(String(name.prefix(1)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isYou ? .black : .white)
                    .frame(width: 28, height: 28)
                    .background(isYou ? result.medalColor : Color.cardInset, in: Circle())
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(isYou ? 0.32 : 1.0))
                .frame(height: barHeight)
                .overlay(alignment: .top) {
                    Text(rankOrdinal(rank))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isYou ? result.medalColor : .secondary)
                        .padding(.top, 6)
                }
        }
        .frame(maxWidth: .infinity)
    }
}

/// FR-B — Split Stats: small medal on the left, a stat stack on the right,
/// divided down the middle. No dead space on either side.
private struct SplitStatsCard: View {
    let result: MockResult

    var body: some View {
        HStack(spacing: 16) {
            MedallionView(result: result, diameter: 64, glow: false)
                .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.fitnessSeparator)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                splitStat("Place", value: "\(rankOrdinal(result.rank)) of \(result.total)", color: result.medalColor)
                splitStat("Points", value: Int(result.points).formatted(), color: .exerciseRing)
                if result.isWinner, result.marginOverNext > 0 {
                    splitStat("Margin", value: "+\(Int(result.marginOverNext).formatted())", color: .standRing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func splitStat(_ label: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

/// FR-C — Hero Row: your own leaderboard row blown up into the header,
/// edge to edge — rank, avatar, name, points.
private struct HeroRowCard: View {
    let result: MockResult

    var body: some View {
        HStack(spacing: 14) {
            Text(rankOrdinal(result.rank))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(result.medalColor)

            Text("S")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.exerciseRing, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(result.isWinner ? "You won" : "You")
                    .font(.system(size: 17, weight: .semibold))
                Text(result.challengeName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text(Int(result.points).formatted())
                    .font(.leaderboardPoints())
                Text("pts")
                    .font(.leaderboardSecondary())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// FR-D — Confetti Fill: the baseline text, but the blank space earns its
/// keep with a scatter of ring-colored confetti dots.
private struct ConfettiFillCard: View {
    let result: MockResult

    /// Deterministic scatter: (x, y) in unit space, size, color index.
    private static let confetti: [(x: CGFloat, y: CGFloat, s: CGFloat, c: Int)] = [
        (0.06, 0.18, 5, 0), (0.13, 0.62, 4, 1), (0.21, 0.32, 6, 2),
        (0.09, 0.85, 5, 2), (0.27, 0.74, 4, 0), (0.18, 0.08, 4, 1),
        (0.79, 0.14, 5, 1), (0.88, 0.45, 6, 0), (0.94, 0.75, 4, 2),
        (0.72, 0.58, 4, 2), (0.85, 0.88, 5, 1), (0.93, 0.24, 4, 0),
        (0.33, 0.15, 4, 2), (0.68, 0.82, 4, 0),
    ]
    private static let palette: [Color] = [.moveRing, .exerciseRing, .standRing]

    var body: some View {
        VStack(spacing: 4) {
            Text(rankOrdinal(result.rank))
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(result.medalColor)
            Text(result.isWinner ? "You won \(result.challengeName)" : "\(result.challengeName) complete")
                .font(.system(size: 17, weight: .bold))
            Text("\(Int(result.points).formatted()) pts • \(result.total) participants")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                ForEach(Array(Self.confetti.enumerated()), id: \.offset) { _, dot in
                    Circle()
                        .fill(Self.palette[dot.c].opacity(result.isWinner ? 0.55 : 0.18))
                        .frame(width: dot.s, height: dot.s)
                        .position(x: geo.size.width * dot.x, y: geo.size.height * dot.y)
                }
            }
            .background(Color.cardBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// FR-E — Wide Banner: laurels stretched to the card edges framing the
/// result, one dense line of type in the middle.
private struct WideBannerCard: View {
    let result: MockResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(result.medalColor)

            VStack(spacing: 3) {
                Text(result.isWinner ? "You won \(result.challengeName)" : "You finished \(rankOrdinal(result.rank))")
                    .font(.system(size: 17, weight: .bold))
                Text("\(rankOrdinal(result.rank)) of \(result.total) • \(Int(result.points).formatted()) pts")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Image(systemName: "laurel.trailing")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(result.medalColor)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Option 2: Workout Summary Grid
//
// The post-workout summary screen: left-aligned stat pairs in a two-column
// grid, gray labels over bold rounded values, each value in its own color.

private struct SummaryGridCard: View {
    let result: MockResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statRow(label: "Final Place",
                    value: "\(rankOrdinal(result.rank)) of \(result.total)",
                    color: result.medalColor)

            Divider().overlay(Color.fitnessSeparator)

            HStack(alignment: .top) {
                stat(label: "Total Points",
                     value: Int(result.points).formatted(),
                     color: .exerciseRing)
                Spacer()
                if result.isWinner {
                    stat(label: "Winning Margin",
                         value: "+\(Int(result.marginOverNext).formatted())",
                         color: .standRing)
                } else {
                    stat(label: "Participants",
                         value: "\(result.total)",
                         color: .standRing)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statRow(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func stat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Option 3: Competition Result Cell
//
// The Fitness Sharing tab's competition cell: a sentence-first result with
// initial-circle avatars, exactly like "You beat Emily in the 7-Day
// Competition".

private struct CompetitionCellCard: View {
    let result: MockResult

    private var headline: String {
        if result.isWinner {
            switch result.othersBeaten.count {
            case 1:  return "You beat \(result.othersBeaten[0])"
            case 2:  return "You beat \(result.othersBeaten[0]) and \(result.othersBeaten[1])"
            default: return "You beat \(result.othersBeaten.count) others"
            }
        } else {
            return "You finished \(rankOrdinal(result.rank)) of \(result.total)"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Overlapping initial circles, like Sharing's competitor pairs.
            HStack(spacing: -10) {
                initialCircle("S", color: .exerciseRing)
                ForEach(Array(result.othersBeaten.prefix(2).enumerated()), id: \.offset) { idx, name in
                    initialCircle(String(name.prefix(1)), color: idx == 0 ? .stepsColor : .standRing)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 16, weight: .semibold))
                Text("\(Int(result.points).formatted()) pts • \(result.challengeName)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(rankMedal(result.rank))
                .font(.system(size: 26))
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func initialCircle(_ letter: String, color: Color) -> some View {
        Text(letter)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(color, in: Circle())
            .overlay(Circle().strokeBorder(Color.cardBackground, lineWidth: 2))
    }
}

// MARK: - Option 4: Ring Dial
//
// The Activity card layout: a ring on the left, stacked metrics on the
// right. The ring closes fully for 1st place and shows your rank inside.

private struct RingDialCard: View {
    let result: MockResult

    /// 1st → full ring, last → barely open. Same idea as closing your rings.
    private var fillFraction: Double {
        guard result.total > 1 else { return 1 }
        return Double(result.total - result.rank + 1) / Double(result.total)
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(result.medalColor.opacity(0.25), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: fillFraction)
                    .stroke(result.medalColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(rankOrdinal(result.rank))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(result.medalColor)
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.isWinner ? "You won" : "Challenge complete")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(Int(result.points).formatted()) pts")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.exerciseRing)
                Text("\(rankOrdinal(result.rank)) of \(result.total) participants")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Option 5: Award Row
//
// The Awards tab treatment: a flat circular award badge with the rank
// numeral, next to a title/subtitle pair — like a Fitness award listing.

private struct AwardRowCard: View {
    let result: MockResult

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(result.medalColor.opacity(0.16))
                Circle()
                    .strokeBorder(result.medalColor, lineWidth: 2.5)
                    .padding(5)
                VStack(spacing: -2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                    Text("\(result.rank)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                }
                .foregroundStyle(result.medalColor)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.isWinner ? "\(result.challengeName) Champion"
                                     : "\(result.challengeName) Finisher")
                    .font(.system(size: 17, weight: .semibold))
                Text(result.isWinner
                     ? "Finished 1st of \(result.total) • \(Int(result.points).formatted()) pts"
                     : "Finished \(rankOrdinal(result.rank)) of \(result.total) • \(Int(result.points).formatted()) pts")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Previews

private struct MockupGallery: View {
    let result: MockResult
    var page: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if page == 1 {
                    labeled("1. Big Number") { BigNumberCard(result: result) }
                    labeled("2. Workout Summary Grid") { SummaryGridCard(result: result) }
                    labeled("3. Competition Result Cell") { CompetitionCellCard(result: result) }
                } else {
                    labeled("4. Ring Dial") { RingDialCard(result: result) }
                    labeled("5. Award Row") { AwardRowCard(result: result) }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }
}

private struct BigNumberIterationsGallery: View {
    let result: MockResult
    var page: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if page == 1 {
                    labeled("1A. Baseline") { BigNumberCard(result: result) }
                    labeled("1B. Value/Suffix Split") { BigNumberSplitCard(result: result) }
                    labeled("1C. Activity Card Layout") { BigNumberActivityCard(result: result) }
                } else {
                    labeled("1D. Rank + Points") { BigNumberPointsCard(result: result) }
                    labeled("1E. Fraction (1st/3)") { BigNumberFractionCard(result: result) }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }
}

private struct MedallionIterationsGallery: View {
    let result: MockResult
    var page: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if page == 1 {
                    labeled("PM-A. Baseline") { PodiumMedallionCard(result: result) }
                    labeled("PM-B. Laurels") { MedallionLaurelsCard(result: result) }
                } else {
                    labeled("PM-C. Ribbon") { MedallionRibbonCard(result: result) }
                    labeled("PM-D. Compact Row") { MedallionRowCard(result: result) }
                    labeled("PM-E. With Points") { MedallionPointsCard(result: result) }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }
}

// PM-A across every rank tier: gold, silver, bronze, and off-podium.
private let sampleRank3 = MockResult(
    rank: 3, total: 5, points: 3120, marginOverNext: 0,
    challengeName: "July 🔥", othersBeaten: ["Maria L", "Dev P"]
)
private let sampleRank4 = MockResult(
    rank: 4, total: 8, points: 2210, marginOverNext: 0,
    challengeName: "July 🔥", othersBeaten: []
)

private struct MedallionRankLadder: View {
    var page: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if page == 1 {
                    labeled("PM-A — 1st (gold)") { PodiumMedallionCard(result: sampleWin) }
                    labeled("PM-A — 2nd (silver)") { PodiumMedallionCard(result: sampleLoss) }
                } else {
                    labeled("PM-A — 3rd (bronze)") { PodiumMedallionCard(result: sampleRank3) }
                    labeled("PM-A — 4th of 8 (off-podium)") { PodiumMedallionCard(result: sampleRank4) }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }
}

private struct FreshIterationsGallery: View {
    let result: MockResult
    var page: Int = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if page == 1 {
                    labeled("FR-A. Podium Chart") { PodiumChartCard(result: result) }
                    labeled("FR-B. Split Stats") { SplitStatsCard(result: result) }
                    labeled("FR-C. Hero Row") { HeroRowCard(result: result) }
                } else {
                    labeled("FR-D. Confetti Fill") { ConfettiFillCard(result: result) }
                    labeled("FR-E. Wide Banner") { WideBannerCard(result: result) }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
    }

    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            content()
        }
    }
}

#Preview("Fresh A–C — Winner") {
    FreshIterationsGallery(result: sampleWin, page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Fresh D–E — Winner") {
    FreshIterationsGallery(result: sampleWin, page: 2)
        .preferredColorScheme(.dark)
}

#Preview("Fresh A–C — 2nd Place") {
    FreshIterationsGallery(result: sampleLoss, page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Fresh D–E — 2nd Place") {
    FreshIterationsGallery(result: sampleLoss, page: 2)
        .preferredColorScheme(.dark)
}

#Preview("PM-A Ranks 1–2") {
    MedallionRankLadder(page: 1)
        .preferredColorScheme(.dark)
}

#Preview("PM-A Ranks 3–4+") {
    MedallionRankLadder(page: 2)
        .preferredColorScheme(.dark)
}

#Preview("Medallion A–B — Winner") {
    MedallionIterationsGallery(result: sampleWin, page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Medallion C–E — Winner") {
    MedallionIterationsGallery(result: sampleWin, page: 2)
        .preferredColorScheme(.dark)
}

#Preview("Medallion A–B — 2nd Place") {
    MedallionIterationsGallery(result: sampleLoss, page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Medallion C–E — 2nd Place") {
    MedallionIterationsGallery(result: sampleLoss, page: 2)
        .preferredColorScheme(.dark)
}

#Preview("Big Number 1A–1C — Winner") {
    BigNumberIterationsGallery(result: sampleWin, page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Big Number 1D–1E — Winner") {
    BigNumberIterationsGallery(result: sampleWin, page: 2)
        .preferredColorScheme(.dark)
}

#Preview("Big Number 1A–1C — 2nd Place") {
    BigNumberIterationsGallery(result: sampleLoss, page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Big Number 1D–1E — 2nd Place") {
    BigNumberIterationsGallery(result: sampleLoss, page: 2)
        .preferredColorScheme(.dark)
}

#Preview("Options 1–3 — Winner") {
    MockupGallery(result: sampleWin, page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Options 4–5 — Winner") {
    MockupGallery(result: sampleWin, page: 2)
        .preferredColorScheme(.dark)
}

#Preview("Options 1–3 — 2nd Place") {
    MockupGallery(result: sampleLoss, page: 1)
        .preferredColorScheme(.dark)
}

#Preview("Options 4–5 — 2nd Place") {
    MockupGallery(result: sampleLoss, page: 2)
        .preferredColorScheme(.dark)
}
