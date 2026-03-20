import SwiftUI

/// Apple Fitness ring colors and semantic palette.
extension Color {
    // Ring colors — match Apple Fitness exactly.
    static let moveRing     = Color(red: 0.980, green: 0.067, blue: 0.310)  // #FA114F
    static let exerciseRing = Color(red: 0.573, green: 0.910, blue: 0.165)  // #92E82A
    static let standRing    = Color(red: 0.118, green: 0.910, blue: 0.910)  // #1EE8E8

    // Non-Watch metric colors
    static let stepsColor        = Color(red: 0.98, green: 0.55, blue: 0.00)  // orange
    static let activeEnergyColor = Color(red: 0.65, green: 0.20, blue: 0.95)  // purple

    // Semantic
    static let appBackground    = Color(.systemGroupedBackground)
    static let cardBackground   = Color(.secondarySystemGroupedBackground)
    static let primaryText      = Color(.label)
    static let secondaryText    = Color(.secondaryLabel)
    static let rankGold         = Color(red: 1.0, green: 0.84, blue: 0.0)
    static let rankSilver       = Color(red: 0.75, green: 0.75, blue: 0.75)
    static let rankBronze       = Color(red: 0.80, green: 0.50, blue: 0.20)
}

extension ShapeStyle where Self == Color {
    static var moveRing:     Color { .moveRing }
    static var exerciseRing: Color { .exerciseRing }
    static var standRing:    Color { .standRing }
}
