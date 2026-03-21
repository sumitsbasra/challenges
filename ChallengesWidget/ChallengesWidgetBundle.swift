import WidgetKit
import SwiftUI

/// Widget bundle entry point for the ChallengesWidget extension target.
///
/// To add this target in Xcode:
///   File > New > Target > Widget Extension
///   Name: ChallengesWidget
///   Uncheck "Include Configuration Intent" (uses StaticConfiguration)
@main
struct ChallengesWidgetBundle: WidgetBundle {
    var body: some Widget {
        ChallengesRankWidget()
    }
}
