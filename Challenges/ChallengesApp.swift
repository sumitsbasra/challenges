import SwiftUI
import BackgroundTasks

@main
struct ChallengesApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = UserSession.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}

// MARK: - Root content routing

struct ContentView: View {
    @Environment(UserSession.self) private var session

    var body: some View {
        if session.isAuthenticated {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Environment(UserSession.self) private var session

    var body: some View {
        TabView {
            ChallengesListView()
                .tabItem {
                    Label("Challenges", systemImage: "trophy")
                }

            // Activity tab — shortcut to the current active challenge leaderboard,
            // or an empty state when there are no active challenges.
            ActivityTabView()
                .tabItem {
                    Label("Activity", systemImage: "figure.run")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
        .task {
            // Sync on foreground.
            await SyncCoordinator.shared.syncCurrentChallenges()
            BackgroundTaskScheduler.scheduleAppRefresh()

            // Register CloudKit subscriptions for active challenges.
            if let userID = session.userID {
                let challenges = (try? await CloudKitManager.shared.fetchChallenges(forUserID: userID)) ?? []
                let activeIDs = challenges.filter { $0.status == .active }.map { $0.id }
                await CloudKitManager.shared.registerSubscriptions(forActiveChallengeIDs: activeIDs)
            }
        }
    }
}

/// Placeholder Activity tab — shows the user's current rank across active challenges.
struct ActivityTabView: View {
    @Environment(UserSession.self) private var session
    @State private var activeChallenges: [Challenge] = []

    var body: some View {
        NavigationStack {
            Group {
                if activeChallenges.isEmpty {
                    EmptyStateView(
                        systemImage: "figure.run",
                        title: "No active challenges",
                        message: "Join or start a challenge to track your activity here."
                    )
                } else {
                    List(activeChallenges) { challenge in
                        NavigationLink(value: challenge) {
                            ActivityRowView(challenge: challenge, currentUserID: session.userID ?? "")
                        }
                    }
                    .navigationDestination(for: Challenge.self) { challenge in
                        ChallengeDetailView(challenge: challenge)
                    }
                }
            }
            .navigationTitle("Activity")
            .task {
                guard let userID = session.userID else { return }
                let all = (try? await CloudKitManager.shared.fetchChallenges(forUserID: userID)) ?? []
                activeChallenges = all.filter { $0.status == .active }
            }
        }
    }
}

private struct ActivityRowView: View {
    let challenge: Challenge
    let currentUserID: String

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(challenge.title).font(.headline)
                Text("\(challenge.daysRemainingText)")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.secondaryText)
        }
    }
}

private extension Challenge {
    var daysRemainingText: String {
        let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
        return "\(days) day\(days == 1 ? "" : "s") left"
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundTaskScheduler.registerTasks()
        return true
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            let result = await SubscriptionHandler.handle(userInfo: userInfo)
            completionHandler(result)
        }
    }
}
