import SwiftUI
import BackgroundTasks
import CoreSpotlight

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
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

// MARK: - Tab View

struct MainTabView: View {
    @Environment(UserSession.self) private var session

    var body: some View {
        TabView {
            ChallengesListView()
                .tabItem {
                    Label("Challenges", systemImage: "trophy.fill")
                }

            ActivityTabView()
                .tabItem {
                    Label("Activity", systemImage: "figure.run")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle.fill")
                }
        }
        // Tint the selected tab item with the exercise ring green, matching Apple Fitness.
        .tint(.exerciseRing)
        // Handle challenges://challenge/<id> deep links from the widget and share sheets.
        .onOpenURL { url in
            guard url.scheme == "challenges",
                  url.host == "challenge",
                  let challengeID = url.pathComponents.dropFirst().first
            else { return }
            NotificationCenter.default.post(
                name: .openChallenge,
                object: nil,
                userInfo: ["challengeID": challengeID]
            )
        }
        .task {
            await SyncCoordinator.shared.syncCurrentChallenges()
            BackgroundTaskScheduler.scheduleAppRefresh()

            guard let userID = session.userID else { return }
            let challenges = (try? await CloudKitManager.shared.fetchChallenges(forUserID: userID)) ?? []
            let activeIDs = challenges.filter { $0.status == .active }.map { $0.id }
            await CloudKitManager.shared.registerSubscriptions(forActiveChallengeIDs: activeIDs)
        }
    }
}

// MARK: - Activity Tab

struct ActivityTabView: View {
    @Environment(UserSession.self) private var session
    @State private var activeChallenges: [Challenge] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoading {
                    ProgressView().tint(.exerciseRing)
                } else if activeChallenges.isEmpty {
                    EmptyStateView(
                        systemImage: "figure.run",
                        title: "No active challenges",
                        message: "Join or start a challenge to see your live activity here."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(activeChallenges) { challenge in
                                NavigationLink(value: challenge) {
                                    ActiveChallengeRowView(challenge: challenge)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                    .navigationDestination(for: Challenge.self) { challenge in
                        ChallengeDetailView(challenge: challenge)
                    }
                }
            }
            .navigationTitle("Activity")
            .toolbarBackground(Color.appBackground, for: .navigationBar)
        }
        .task {
            isLoading = true
            guard let userID = session.userID else { isLoading = false; return }
            let all = (try? await CloudKitManager.shared.fetchChallenges(forUserID: userID)) ?? []
            activeChallenges = all.filter { $0.status == .active }
            isLoading = false
        }
    }
}

// MARK: - Active Challenge Row (Activity Tab)

private struct ActiveChallengeRowView: View {
    let challenge: Challenge

    private var daysLeft: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: challenge.endDate).day ?? 0)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Ring icon cluster
            ZStack {
                Circle()
                    .fill(Color.exerciseRing.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "figure.run")
                    .font(.title3)
                    .foregroundStyle(.exerciseRing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(challenge.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundTaskScheduler.registerTasks()
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

    /// Handles NSUserActivity continuations from:
    /// - Siri / Apple Intelligence intent invocations (ShowChallengeIntent)
    /// - NSUserActivity donations made in ChallengeDetailView
    /// - Core Spotlight tap-throughs (CSSearchableItemActionType)
    /// - Handoff from other devices
    ///
    /// All paths resolve to the same `openChallenge` notification, which
    /// ChallengesListView observes to navigate programmatically.
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
