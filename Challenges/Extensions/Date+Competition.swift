import Foundation

extension Date {
    /// Returns the start of the calendar day in the local timezone.
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    /// Returns the end of the calendar day (start of next day minus 1 second).
    var endOfDay: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return Calendar.current.date(byAdding: .second, value: -1, to: tomorrow) ?? tomorrow
    }

    /// True if this date is within the competition window [start, end].
    func isInCompetition(start: Date, end: Date) -> Bool {
        self >= start.startOfDay && self <= end.endOfDay
    }

    /// Returns a relative label like "Day 3 of 7" given a competition start date.
    func competitionDayLabel(startDate: Date, totalDays: Int = 7) -> String {
        let cal = Calendar.current
        let day = cal.dateComponents([.day], from: cal.startOfDay(for: startDate),
                                     to: cal.startOfDay(for: self)).day ?? 0
        return "Day \(day + 1) of \(totalDays)"
    }
}
