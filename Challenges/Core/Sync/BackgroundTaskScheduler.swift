import Foundation
import BackgroundTasks

/// Registers and schedules BGAppRefreshTask for periodic sync during active challenges.
enum BackgroundTaskScheduler {

    static let syncTaskID = "com.challenges.sync"

    static func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleAppRefresh(task: refreshTask)
        }
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: syncTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 15 minutes minimum
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh before doing any work.
        scheduleAppRefresh()

        let syncTask = Task {
            await SyncCoordinator.shared.syncCurrentChallenges()
            // Guard against double-completion: if the expiration handler already fired
            // and cancelled this Task, skip the success callback to avoid calling
            // setTaskCompleted twice (which logs a BGTask warning).
            guard !Task.isCancelled else { return }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
