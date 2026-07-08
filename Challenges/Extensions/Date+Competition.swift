import Foundation

extension Date {
    /// Returns the start of the calendar day in the local timezone.
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    /// Returns the end of the calendar day (start of next day minus 1 second).
    var endOfDay: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return Calendar.current.date(byAdding: .second, value: -1, to: tomorrow) ?? tomorrow
    }

}
