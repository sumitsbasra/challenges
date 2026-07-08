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

        case "user-reactions":
            await handleReaction(queryNotification)
            return .newData

        case "challenge-joins":
            await handleJoin(queryNotification)
            return .newData

        default:
            return .noData
        }
    }

    /// Raises a local notification when someone joins one of the user's challenges
    /// and nudges open views to refresh their participant lists.
    private static func handleJoin(_ notification: CKQueryNotification) async {
        let fields = notification.recordFields ?? [:]

        // The subscription covers every participation in the user's challenges,
        // including the user's own join on another device — don't notify for those.
        let joinerID = (fields["userRef"] as? CKRecord.Reference)?.recordID.recordName
        let myUserID = UserSession.shared.userID
        if let joinerID, joinerID == myUserID { return }

        await MainActor.run {
            NotificationCenter.default.post(name: .participationDidChange, object: nil)
        }

        guard UserDefaults.standard.object(forKey: "notif.joins") as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let name = fields["displayName"] as? String ?? "Someone"
        let challengeID = (fields["challengeRef"] as? CKRecord.Reference)?.recordID.recordName
        // Participation records don't carry the challenge title; the local challenge
        // cache resolves it without a CloudKit round trip.
        let challengeTitle = myUserID.flatMap { userID in
            challengeID.flatMap { id in
                ChallengeCache.load(userID: userID)?.challenges.first { $0.id == id }?.title
            }
        }

        let content = UNMutableNotificationContent()
        content.title = "New challenger 🔥"
        content.body  = challengeTitle.map { "\(name) just joined \($0)." }
                     ?? "\(name) just joined your challenge."
        content.sound = .default
        if let challengeID { content.userInfo = ["challengeID": challengeID] }

        let request = UNNotificationRequest(
            identifier: "ch-join-\(notification.recordID?.recordName ?? UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )
        try? await center.add(request)
    }

    /// Raises a local notification for an incoming reaction and nudges any open
    /// leaderboard to refresh. The subscription ships the display fields with the
    /// push (`desiredKeys`), so no CloudKit fetch is needed here.
    private static func handleReaction(_ notification: CKQueryNotification) async {
        let fields = notification.recordFields ?? [:]
        let challengeID = (fields["challengeRef"] as? CKRecord.Reference)?.recordID.recordName ?? ""

        await MainActor.run {
            NotificationCenter.default.post(
                name: .reactionReceived,
                object: nil,
                userInfo: ["challengeID": challengeID]
            )
        }

        guard UserDefaults.standard.object(forKey: "notif.reactions") as? Bool ?? true else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let fromName = fields["fromName"] as? String ?? "Someone"
        let emoji    = fields["emoji"] as? String ?? "🔥"
        let title    = fields["challengeTitle"] as? String

        let content = UNMutableNotificationContent()
        content.title = "\(fromName) sent you \(emoji)"
        content.body  = title.map { "Send a reaction back from the \($0) leaderboard." }
                     ?? "Send a reaction back from the leaderboard."
        content.sound = .default
        if !challengeID.isEmpty { content.userInfo = ["challengeID": challengeID] }

        let request = UNNotificationRequest(
            identifier: "ch-reaction-\(notification.recordID?.recordName ?? UUID().uuidString)",
            content: content,
            trigger: nil  // deliver immediately
        )
        try? await center.add(request)
    }
}

extension Notification.Name {
    static let dailyScoreDidUpdate    = Notification.Name("DailyScoreDidUpdate")
    static let participationDidChange = Notification.Name("ParticipationDidChange")
    /// Posted after a successful local rename. userInfo: ["id": String, "title": String]
    static let challengeDidRename     = Notification.Name("ChallengeDidRename")
    /// Posted after a successful date update. userInfo: ["id": String, "startDate": Date, "endDate": Date]
    static let challengeDatesDidChange = Notification.Name("ChallengeDatesDidChange")
    /// Posted when a reaction push arrives. userInfo: ["challengeID": String]
    static let reactionReceived = Notification.Name("ReactionReceived")
}
