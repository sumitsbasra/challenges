import SwiftUI
import BackgroundTasks
import CoreSpotlight
import UserNotifications
import AppIntents

// MARK: - Shared UI Components

/// Reusable dark card container used inside form-style sheets (New Challenge, Join).
struct FitnessFormCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(16)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openChallenge    = Notification.Name("com.challenges.openChallenge")
    static let openNewChallenge = Notification.Name("com.challenges.openNewChallenge")
}

// MARK: - App Entry Point

@main
struct ChallengesApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = UserSession.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                // Prefer dark mode to match Apple Fitness aesthetic;
                // users can override via system settings.
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Root routing

struct ContentView: View {
    @Environment(UserSession.self) private var session

    var body: some View {
        if session.isAuthenticated {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundTaskScheduler.registerTasks()
        UNUserNotificationCenter.current().delegate = self
        // Register App Shortcuts with Siri. Must be called on every launch so
        // iOS keeps the phrase list current. Without this call the shortcuts
        // exist in code but are never surfaced in Siri or the Shortcuts app.
        ChallengesShortcuts.updateAppShortcutParameters()
        // Re-request HealthKit authorization on every launch. HealthKit only presents
        // the permission dialog for types not yet requested, so this is a no-op for
        // users who already have all permissions. It silently picks up any new types
        // added to HealthKitManager.readTypes (e.g. distanceWalkingRunning) for users
        // who onboarded before the new type was added.
        Task {
            // Only touch HealthKit for already-signed-in users. New users grant access
            // during onboarding (the .health step) — requesting here would pop the
            // HealthKit permission dialog before they've even signed in.
            guard UserSession.shared.isAuthenticated else { return }
            // Re-request on launch so users who onboarded before a new data type was
            // added pick it up (a no-op if all types are already authorized).
            try? await HealthKitManager.shared.requestAuthorization()
            // Register HealthKit background delivery so iOS wakes the app to sync scores
            // when new activity data arrives, without the user opening the app.
            HealthKitManager.shared.startBackgroundDelivery()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            let result = await SubscriptionHandler.handle(userInfo: userInfo)
            completionHandler(result)
        }
    }

    /// Handles UNUserNotificationCenter delegate callbacks.
    // ── UNUserNotificationCenterDelegate ──────────────────────────────────────
    // (conformance declared in extension below)

    /// Handles NSUserActivity continuations from:
    /// - Siri / Apple Intelligence intent invocations (ShowChallengeIntent)
    /// - NSUserActivity donations made in ChallengeDetailView
    /// - Core Spotlight tap-throughs (CSSearchableItemActionType)
    /// - Handoff from other devices
    ///
    /// All paths resolve to the same `openChallenge` notification, which
    /// HomeView observes to navigate programmatically.
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        let challengeID: String?

        if userActivity.activityType == CSSearchableItemActionType {
            // Spotlight tap: the identifier is the challenge's CloudKit record name.
            challengeID = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        } else {
            // NSUserActivity (Siri suggestion, Handoff, or custom activity).
            challengeID = userActivity.userInfo?["challengeID"] as? String
        }

        guard let id = challengeID else { return false }

        NotificationCenter.default.post(
            name: .openChallenge,
            object: nil,
            userInfo: ["challengeID": id]
        )
        return true
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Show banner + play sound even when the app is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Deep-link into the relevant challenge when the user taps a notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let challengeID = response.notification.request.content.userInfo["challengeID"] as? String {
            NotificationCenter.default.post(
                name: .openChallenge,
                object: nil,
                userInfo: ["challengeID": challengeID]
            )
        }
        completionHandler()
    }
}
