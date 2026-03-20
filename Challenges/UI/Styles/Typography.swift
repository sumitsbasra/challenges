import SwiftUI

extension Font {
    static func pointsLarge()   -> Font { .system(size: 48, weight: .bold, design: .rounded) }
    static func pointsMedium()  -> Font { .system(size: 28, weight: .bold, design: .rounded) }
    static func pointsSmall()   -> Font { .system(size: 18, weight: .semibold, design: .rounded) }
    static func rankBadge()     -> Font { .system(size: 13, weight: .bold, design: .rounded) }
    static func countdownTimer() -> Font { .system(size: 15, weight: .medium, design: .monospaced) }
}
