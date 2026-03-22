import Foundation
import UIKit
import CloudKit
import UserNotifications

/// Processes incoming CloudKit silent push notifications and routes them
/// to the appropriate feature view models via NotificationCenter.
enum SubscriptionHandler {

    /// Call from `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`.
    static func handle(userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        else { return .noData }

        guard let queryNotification = notification as? CKQueryNotification else {
            return .noData
        }

        let subscriptionID = queryNotification.subscriptionID ?? ""

        switch subscriptionID {
        case "active-daily-scores":
            // Post to leaderboard view models to trigger a targeted re-fetch.
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .dailyScoreDidUpdate,
                    object: nil,
                    userInfo: ["recordID": queryNotification.recordID?.recordName ?? ""]
                )
            }
            // Also trigger a full sync to update local scores.
            await SyncCoordinator.shared.syncCurrentChallenges()
            return .newData

        case "user-participations":
            await MainActor.run {
                NotificationCenter.default.post(name: .participationDidChange, object: nil)
            }
            return .newData

        default:
            return .noData
        }
    }
}

extension Notification.Name {
    static let dailyScoreDidUpdate    = Notification.Name("DailyScoreDidUpdate")
    static let participationDidChange = Notification.Name("ParticipationDidChange")
}
