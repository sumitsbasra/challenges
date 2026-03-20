import Foundation

extension Double {
    /// Formats a points value as an integer string, e.g. "1 234".
    var pointsFormatted: String {
        let formatted = NumberFormatter()
        formatted.numberStyle = .decimal
        return formatted.string(from: NSNumber(value: Int(self))) ?? "\(Int(self))"
    }

    /// Converts a fraction (0.0–2.0) to a percentage string, e.g. "85%".
    var percentageFormatted: String {
        "\(Int(self * 100))%"
    }
}
