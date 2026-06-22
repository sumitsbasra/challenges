import SwiftUI

// MARK: - Daily Breakdown

/// Per-day ring grid for a challenge: date · colored ring arc · points.
/// Scrolls horizontally so it stays roomy regardless of challenge length.
struct DailyBreakdownView: View {
    let participation: Participation
    let challenge: Challenge

    private var allDays: [(date: Date, score: DailyScore?)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: challenge.startDate)
        let end   = cal.startOfDay(for: challenge.endDate)
        let count = min(31, max(1, (cal.dateComponents([.day], from: start, to: end).day ?? 0) + 1))
        return (0..<count).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
            let score = participation.dailyScores.first {
                cal.isDate($0.date, inSameDayAs: day)
            }
            return (day, score)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(allDays, id: \.date) { entry in
                        DayCell(date: entry.date, score: entry.score)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 6)
            }

            Text("Max 600 pts / day")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
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
        VStack(spacing: 8) {
            // Date label, e.g. "6/19"
            Text(date.formatted(.dateTime.month(.defaultDigits).day()))
                .font(.system(size: 11, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : Color.secondary)
                .fixedSize()

            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.15), lineWidth: ringLineWidth)

                if !isFuture && pts > 0 {
                    Circle()
                        .trim(from: 0, to: fillFraction)
                        .stroke(ringColor,
                                style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }

                if !isFuture {
                    Text(centerLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(pts > 0 ? ringColor : Color.secondary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .frame(width: cellSize, height: cellSize)

            Circle()
                .fill(isToday ? Color.white : Color.clear)
                .frame(width: 4, height: 4)
        }
    }

    private var cellSize: CGFloat { 46 }
    private var ringLineWidth: CGFloat { 4 }

    /// Fill fraction capped at 1.0 (full circle = 600 pts)
    private var fillFraction: Double { min(pts / 600.0, 1.0) }

    private var ringColor: Color {
        if isFuture || pts == 0 { return Color(.systemGray4) }
        if pts >= 500 { return .moveRing }
        if pts >= 300 { return .exerciseRing }
        return .stepsColor
    }

    private var centerLabel: String {
        if pts == 0 { return "–" }
        return pts >= 1000 ? String(format: "%.0fk", pts / 1000) : "\(Int(pts))"
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
                        date: Calendar.current.date(byAdding: .day, value: i, to: Date())!,
                        points: Double([862, 374, 260, 589, 253][i]),
                        ringData: RingData(moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
                                          stepsPct: 0, activeEnergyPct: 0, syncSource: .watch),
                        lastSyncedAt: Date()
                    )
                },
                totalPoints: 2338, rank: 2
            ),
            challenge: Challenge(
                id: "c1", title: "Summer", creatorID: "u1",
                startDate: Date(),
                endDate: Calendar.current.date(byAdding: .day, value: 13, to: Date())!,
                status: .active, inviteCode: "ABC123", createdAt: Date()
            )
        )
        .padding(.horizontal, 16)
        .preferredColorScheme(.dark)
    }
}
