import SwiftUI

// MARK: - Daily Breakdown

/// 7-column week grid matching Apple Fitness's weekly activity overview:
/// day letter · colored ring arc · points number · "today" indicator.
struct DailyBreakdownView: View {
    let participation: Participation
    let challengeStartDate: Date

    private var allDays: [(date: Date, score: DailyScore?)] {
        (0..<7).map { offset in
            let day = Calendar.current.date(byAdding: .day, value: offset, to: challengeStartDate)!
            let score = participation.dailyScores.first {
                Calendar.current.isDate($0.date, inSameDayAs: day)
            }
            return (day, score)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Day cells
            HStack(spacing: 4) {
                ForEach(allDays, id: \.date) { entry in
                    DayCell(date: entry.date, score: entry.score)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 4)

            // Legend
            HStack {
                Spacer()
                Text("Max 600 pts / day")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.bottom, 14)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let score: DailyScore?

    private var isToday:  Bool { Calendar.current.isDateInToday(date) }
    private var isFuture: Bool { date > Date() }
    private var pts: Double { score?.points ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            // Day letter (Mon → M)
            Text(dayLetter)
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : Color.secondary)

            // Circular progress indicator
            ZStack {
                // Dark track
                Circle()
                    .stroke(ringColor.opacity(0.15), lineWidth: ringLineWidth)

                // Fill arc
                if !isFuture && pts > 0 {
                    Circle()
                        .trim(from: 0, to: fillFraction)
                        .stroke(
                            ringColor,
                            style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                // Center content
                if isFuture {
                    // No content — future days are empty
                } else {
                    Text(centerLabel)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(pts > 0 ? ringColor : Color.secondary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .frame(width: cellSize, height: cellSize)

            // "Today" dot indicator
            Circle()
                .fill(isToday ? Color.white : Color.clear)
                .frame(width: 4, height: 4)
        }
    }

    // MARK: - Computed

    private var cellSize: CGFloat { 38 }
    private var ringLineWidth: CGFloat { 3.5 }

    private var dayLetter: String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    /// Fill fraction capped at 1.0 (full circle = 600 pts)
    private var fillFraction: Double {
        min(pts / 600.0, 1.0)
    }

    private var ringColor: Color {
        if isFuture || pts == 0 { return Color(.systemGray4) }
        if pts >= 500 { return .moveRing }
        if pts >= 300 { return .exerciseRing }
        return .stepsColor
    }

    private var centerLabel: String {
        if pts == 0 { return "–" }
        return pts >= 1000
            ? String(format: "%.0fk", pts / 1000)
            : "\(Int(pts))"
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        DailyBreakdownView(
            participation: Participation(
                id: "p1", challengeID: "c1",
                user: AppUser(id: "u1", displayName: "Alex", appleUserID: "a", hasAppleWatch: true),
                joinedAt: Date(), status: .active, hasAppleWatch: true,
                dailyScores: (0..<5).map { i in
                    DailyScore(
                        id: "s\(i)", participationID: "p1", challengeID: "c1",
                        date: Calendar.current.date(byAdding: .day, value: -6 + i, to: Date())!,
                        points: Double([0, 280, 480, 600, 390][i]),
                        ringData: RingData(moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                                          stepsPct: 0, activeEnergyPct: 0, syncSource: .watch),
                        lastSyncedAt: Date()
                    )
                },
                totalPoints: 1850, rank: 1
            ),
            challengeStartDate: Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        )
        .padding(.horizontal, 16)
    }
}
