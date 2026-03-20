import SwiftUI

/// 7-day grid showing each day's points for the current user.
struct DailyBreakdownView: View {
    let participation: Participation
    let challengeStartDate: Date

    private var allDays: [(date: Date, score: DailyScore?)] {
        var result: [(date: Date, score: DailyScore?)] = []
        let calendar = Calendar.current
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: challengeStartDate)!
            let score = participation.dailyScores.first {
                calendar.isDate($0.date, inSameDayAs: day)
            }
            result.append((day, score))
        }
        return result
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(allDays, id: \.date) { entry in
                DayCell(date: entry.date, score: entry.score)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct DayCell: View {
    let date: Date
    let score: DailyScore?

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isFuture: Bool { date > Date() }

    var body: some View {
        VStack(spacing: 4) {
            Text(dayLetter)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.secondaryText)

            ZStack {
                Circle()
                    .fill(cellBackground)
                    .frame(width: 36, height: 36)
                if isFuture {
                    Image(systemName: "minus")
                        .font(.caption)
                        .foregroundStyle(Color.secondaryText)
                } else {
                    Text(scoreText)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreTextColor)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var dayLetter: String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private var scoreText: String {
        guard let pts = score?.points else { return "0" }
        return pts >= 1000 ? String(format: "%.0fk", pts / 1000) : "\(Int(pts))"
    }

    private var cellBackground: Color {
        if isFuture { return Color(.systemGray5) }
        guard let pts = score?.points else { return Color(.systemGray5) }
        if pts >= 400 { return Color.moveRing.opacity(0.9) }
        if pts >= 200 { return Color.stepsColor.opacity(0.8) }
        return Color(.systemGray4)
    }

    private var scoreTextColor: Color {
        guard let pts = score?.points, pts > 0 else { return .secondaryText }
        return .white
    }
}
