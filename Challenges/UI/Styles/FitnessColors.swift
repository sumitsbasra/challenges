import SwiftUI

// MARK: - Ring Colors

extension Color {

    // Apple Fitness exact ring colors
    static let moveRing     = Color(red: 0.980, green: 0.067, blue: 0.310)  // #FA114F
    static let exerciseRing = Color(red: 0.573, green: 0.910, blue: 0.165)  // #92E82A
    static let standRing    = Color(red: 0.118, green: 0.910, blue: 0.910)  // #1EE8E8

    // Non-Watch metric colors — vivid on dark backgrounds
    static let stepsColor        = Color(red: 1.00, green: 0.58, blue: 0.00)  // #FF9400
    static let activeEnergyColor = Color(red: 0.42, green: 0.35, blue: 0.96)  // #6B59F5

    // MARK: - Surfaces (semantic system colors — correct in light + dark)
    //
    // In dark mode:
    //   systemBackground          → #000000 (true black, like Apple Fitness)
    //   secondarySystemBackground → #1C1C1E (card surfaces)
    //   tertiarySystemBackground  → #2C2C2E (inset/nested surfaces)
    static let appBackground  = Color(.systemBackground)
    static let cardBackground = Color(UIColor.secondarySystemBackground)
    static let cardInset      = Color(UIColor.tertiarySystemBackground)

    // MARK: - Text
    static let primaryText   = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText  = Color(.tertiaryLabel)

    // MARK: - Rank medals
    static let rankGold   = Color(red: 1.00, green: 0.84, blue: 0.00)
    static let rankSilver = Color(red: 0.75, green: 0.75, blue: 0.75)
    static let rankBronze = Color(red: 0.80, green: 0.50, blue: 0.20)

    // MARK: - Separator
    static let fitnessSeparator = Color(UIColor.separator)
}

extension ShapeStyle where Self == Color {
    static var moveRing:     Color { .moveRing }
    static var exerciseRing: Color { .exerciseRing }
    static var standRing:    Color { .standRing }
}
