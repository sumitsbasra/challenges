import SwiftUI
import HealthKit
import CloudKit
import OSLog

// MARK: - ViewModel

@Observable
final class HomeViewModel {

    // MARK: Rings (from HealthKit)

    var ringData: RingData = RingData(
        moveRingPct: 0, exerciseRingPct: 0, standRingPct: 0,
        stepsPct: 0, activeEnergyPct: 0, syncSource: .iphone
    )
    var steps: Double = 0
    var activeEnergy: Double = 0
    var exerciseMinutes: Double = 0
    var standHours: Double = 0
    var moveGoal: Double = 700
    var exerciseGoal: Double = 30
    var standGoal: Double = 12
    var stepsGoal: Double = 10_000
    var energyGoal: Double = 500
    var isLoadingRings = true
    var hasWatch: Bool = UserDefaults.standard.bool(forKey: "hasAppleWatch")

    // MARK: Challenges

    /// Active challenges with rank + points data.
    var activeItems: [TodayItem] = []
    /// Completed challenges with final rank data.
    var completedItems: [TodayItem] = []
    /// Upcoming (pending) challenges — shown below active.
    var upcomingChallenges: [Challenge] = []
    /// Completed challenges — hidden unless showCompleted = true.
    var completedChallenges: [Challenge] = []
    /// All challenges flat — used for deep-link lookups.
    var allChallenges: [Challenge] = []

    /// True only on the very first load when there is no cached data.
    var isLoadingChallenges = false
    /// True while a background refresh is in progress (cached data is already shown).
    var isRefreshingChallenges = false
    var showCompleted = false
    var error: String? = nil

    private let ck = CloudKitManager.shared

    // MARK: - Init

    init() {
        // Pre-populate from cache so the very first SwiftUI frame already has data.
        // Without this, the view renders with empty arrays, shows "No challenges yet"
        // for a visible moment, then replaces it once .task fires and reads the cache.
        // Reading from UserDefaults/disk here is synchronous and fast (<1 ms).
        guard let userID = UserSession.shared.userID,
              let cached = ChallengeCache.load(userID: userID) else { return }
        allChallenges       = cached.challenges
        activeItems         = cached.activeItems
        completedItems      = cached.completedItems
        upcomingChallenges  = cached.challenges.filter { $0.status == .pending }
        completedChallenges = cached.challenges.filter { $0.status == .completed }
    }

    // MARK: - Load

    @MainActor
    func load(userID: String) async {
        await loadRings()
        await loadChallenges(userID: userID)
    }

    // MARK: - Rings

    @MainActor
    func loadRings() async {
        isLoadingRings = true
        defer { isLoadingRings = false }

        // Re-detect Watch every load to catch stale flags from onboarding.
        let detected = await WatchDetector().detectAppleWatch()
        if detected != hasWatch {
            hasWatch = detected
            UserDefaults.standard.set(detected, forKey: "hasAppleWatch")
            if var user = UserSession.shared.currentUser {
                user.hasAppleWatch = detected
                UserSession.shared.update(user: user)
                try? await CloudKitManager.shared.saveUser(user)
            }
        }

        let fetcher = ActivityDataFetcher()
        let today = Date()
        let calendar = Calendar.current

        if hasWatch {
            let summaries = await fetcher.activitySummaries(from: today, to: today)
            let key = calendar.startOfDay(for: today)
            if let summary = summaries[key] {
                let moveGoal  = summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie())
                let moveDone  = summary.activeEnergyBurned.doubleValue(for: .kilocalorie())
                let exGoal    = summary.appleExerciseTimeGoal.doubleValue(for: .minute())
                let exDone    = summary.appleExerciseTime.doubleValue(for: .minute())
                let standGoal = summary.appleStandHoursGoal.doubleValue(for: .count())
                let standDone = summary.appleStandHours.doubleValue(for: .count())

                activeEnergy    = moveDone
                exerciseMinutes = exDone
                standHours      = standDone
                self.moveGoal     = max(moveGoal, 1)
                self.exerciseGoal = max(exGoal, 1)
                self.standGoal    = max(standGoal, 1)
                ringData = RingData(
                    moveRingPct:     moveGoal  > 0 ? moveDone  / moveGoal  : 0,
                    exerciseRingPct: exGoal    > 0 ? exDone    / exGoal    : 0,
                    standRingPct:    standGoal > 0 ? standDone / standGoal : 0,
                    stepsPct: 0, activeEnergyPct: 0,
                    syncSource: .watch
                )
            } else {
                // Activity summary not yet available for today (common early in the morning
                // before the first workout event triggers a Watch sync). Fall back to
                // individual HealthKit queries, which are populated even without a summary.
                async let energyTask   = fetcher.activeEnergy(on: today)
                async let exerciseTask = fetcher.exerciseMinutes(on: today)
                async let standTask    = fetcher.standHours(on: today)
                let (e, ex, st) = await (energyTask ?? 0, exerciseTask ?? 0, standTask ?? 0)

                let goalMoveVal = await GoalResolver().moveGoal()
                activeEnergy    = e
                exerciseMinutes = ex
                standHours      = st
                self.moveGoal     = max(goalMoveVal, 1)
                self.exerciseGoal = 30
                self.standGoal    = 12
                ringData = RingData(
                    moveRingPct:     goalMoveVal > 0 ? e  / goalMoveVal : 0,
                    exerciseRingPct: ex / 30,
                    standRingPct:    st / 12,
                    stepsPct: 0, activeEnergyPct: 0,
                    syncSource: .watch
                )
            }
        } else {
            async let stepsTask    = fetcher.steps(on: today)
            async let energyTask   = fetcher.activeEnergy(on: today)
            async let exerciseTask = fetcher.exerciseMinutes(on: today)
            let (s, e, ex) = await (stepsTask ?? 0, energyTask ?? 0, exerciseTask ?? 0)
            steps           = s
            activeEnergy    = e
            exerciseMinutes = ex
            let goalResolver  = GoalResolver()
            let stepsGoalVal  = goalResolver.stepsGoal
            let energyGoalVal = goalResolver.activeEnergyGoal
            let exerciseGoalVal = GoalResolver.defaultExerciseGoalMinutes
            self.stepsGoal    = stepsGoalVal
            self.energyGoal   = energyGoalVal
            self.exerciseGoal = exerciseGoalVal
            ringData = RingData(
                moveRingPct: 0,
                exerciseRingPct: exerciseGoalVal > 0 ? ex / exerciseGoalVal : 0,
                standRingPct: 0,
                stepsPct:        stepsGoalVal  > 0 ? s / stepsGoalVal  : 0,
                activeEnergyPct: energyGoalVal > 0 ? e / energyGoalVal : 0,
                syncSource: .iphone
            )
        }
    }

    // MARK: - Challenges

    @MainActor
    func loadChallenges(userID: String) async {
        // If we already have data (pre-populated by init or a previous load), show the
        // subtle refresh indicator rather than a blank loading state.
        // If this is a first launch with no cache, show the full loading indicator.
        if !activeItems.isEmpty || !upcomingChallenges.isEmpty {
            isRefreshingChallenges = true
        } else if let cached = ChallengeCache.load(userID: userID) {
            // Cache exists but init() didn't run for this userID (e.g. account switch).
            // Apply local status transitions so badge text is correct before network fetch.
            let locallyTransitioned = applyLocalTransitions(cached.challenges, fireCloudKit: false)
            applyAll(locallyTransitioned, activeItems: cached.activeItems, completedItems: cached.completedItems)
            isRefreshingChallenges = true
        } else {
            isLoadingChallenges = true
        }

        defer {
            isLoadingChallenges = false
            isRefreshingChallenges = false
        }

        do {
            let fetched = try await ck.fetchChallenges(forUserID: userID)
            // Immediately transition any challenges whose window has opened or closed,
            // and fire CloudKit updates in the background so other clients see the change.
            let all = applyLocalTransitions(fetched, fireCloudKit: true)
            // Run both builds concurrently — each fetches a disjoint set of challenges.
            async let activeBuild   = buildRankedItems(from: all, status: .active,    userID: userID)
            async let completedBuild = buildRankedItems(from: all, status: .completed, userID: userID)
            let (activeResult, completedResult) = await (activeBuild, completedBuild)
            let active    = activeResult.items
            let completed = completedResult.items
            let seenIDs   = Set([userID])
                .union(activeResult.participantIDs)
                .union(completedResult.participantIDs)
            applyAll(all, activeItems: active, completedItems: completed)
            // Clear any stale error banner now that a load has succeeded.
            self.error = nil
            // Immediately patch today's points from the in-memory ring data so every
            // reload trigger (navigation pop, CloudKit push, participation change) shows
            // live activity values without waiting for another HealthKit sync.
            patchTodayPointsFromRingData()
            ChallengeCache.save(challenges: all, activeItems: active, completedItems: completed, userID: userID)
            // Prune avatars for users no longer in any of our challenges.
            Task.detached { AvatarCache.pruneStale(keepingUserIDs: seenIDs) }
            SpotlightIndexer.index(all)
            Task { await NotificationScheduler.reschedule(for: all) }
            // Backfill scores for recently-completed challenges (ended within the last
            // 2 days) so final standings populate without opening each one. syncChallenge
            // no-ops on days that already have points, so this is cheap on repeat loads.
            let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
            let recentlyCompleted = all.filter { $0.status == .completed && $0.endDate > twoDaysAgo }
            if !recentlyCompleted.isEmpty {
                Task.detached {
                    for challenge in recentlyCompleted {
                        _ = await SyncCoordinator.shared.syncChallenge(challenge)
                    }
                }
            }
        } catch {
            let ckError = error as? CKError
            Logger.cloudKit.error("loadChallenges failed: code=\(ckError?.code.rawValue ?? -1, privacy: .public) \(error.localizedDescription, privacy: .public)")
            // Don't cry wolf: if cached challenges are already on screen, a failed
            // background refresh stays silent and retries on the next trigger. Only
            // surface a banner when there's genuinely nothing to show (or a hard
            // iCloud auth problem the user must act on).
            let hasData = !activeItems.isEmpty || !upcomingChallenges.isEmpty || !completedItems.isEmpty
            if ckError?.code == .notAuthenticated {
                self.error = "iCloud sign-in required. Check Settings → iCloud."
            } else if !hasData {
                if ckError?.code == .networkUnavailable || ckError?.code == .networkFailure {
                    self.error = "No internet connection."
                } else {
                    self.error = "Couldn't refresh. Pull down to try again."
                }
            }
        }
    }

    @MainActor
    private func applyAll(_ all: [Challenge], activeItems: [TodayItem], completedItems: [TodayItem]) {
        allChallenges        = all
        self.activeItems     = activeItems
        self.completedItems  = completedItems
        upcomingChallenges   = all.filter { $0.status == .pending }
        completedChallenges  = all.filter { $0.status == .completed }
    }

    /// Patches a challenge's title across every in-memory collection — no CloudKit fetch needed.
    @MainActor
    func applyRename(id: String, title: String) {
        func patchChallenge(_ c: inout Challenge) { if c.id == id { c.title = title } }
        for i in allChallenges.indices       { patchChallenge(&allChallenges[i]) }
        for i in upcomingChallenges.indices  { patchChallenge(&upcomingChallenges[i]) }
        for i in completedChallenges.indices { patchChallenge(&completedChallenges[i]) }
        activeItems    = activeItems.map    { patchItem($0, id: id) { c in c.title = title } }
        completedItems = completedItems.map { patchItem($0, id: id) { c in c.title = title } }
    }

    /// Patches a challenge's dates across every in-memory collection — no CloudKit fetch needed.
    @MainActor
    func applyDateUpdate(id: String, startDate: Date, endDate: Date) {
        func patchChallenge(_ c: inout Challenge) {
            if c.id == id { c.startDate = startDate; c.endDate = endDate }
        }
        for i in allChallenges.indices       { patchChallenge(&allChallenges[i]) }
        for i in upcomingChallenges.indices  { patchChallenge(&upcomingChallenges[i]) }
        for i in completedChallenges.indices { patchChallenge(&completedChallenges[i]) }
        activeItems    = activeItems.map    { patchItem($0, id: id) { c in c.startDate = startDate; c.endDate = endDate } }
        completedItems = completedItems.map { patchItem($0, id: id) { c in c.startDate = startDate; c.endDate = endDate } }
    }

    /// Applies `pending → active` and `active → completed` transitions based on the
    /// current date. When `fireCloudKit` is true, writes each transition to CloudKit in
    /// the background — used on a fresh network fetch so other clients see the update.
    @MainActor
    private func applyLocalTransitions(_ challenges: [Challenge], fireCloudKit: Bool) -> [Challenge] {
        let now = Date()
        var result = challenges
        for i in result.indices {
            let c = result[i]
            if c.status == .pending && c.startDate <= now {
                result[i].status = .active
                if fireCloudKit {
                    let id = c.id
                    Task { try? await CloudKitManager.shared.updateChallengeStatus(id, status: .active) }
                }
            } else if c.status == .active && c.endDate < now {
                result[i].status = .completed
                if fireCloudKit {
                    let id = c.id
                    Task { try? await CloudKitManager.shared.updateChallengeStatus(id, status: .completed) }
                }
            }
        }
        return result
    }

    /// Patches today's points and total points on active home cards using freshly synced
    /// HealthKit scores. Called after `syncCurrentChallenges` so the cards never show
    /// stale "+0 today" values caused by CloudKit read-after-write latency.
    @MainActor
    func applySyncedScores(_ syncedScores: [String: [DailyScore]]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        activeItems = activeItems.map { item in
            guard let scores = syncedScores[item.id] else { return item }
            let todayPts = scores
                .first(where: { cal.isDateInToday($0.date) })?.points ?? item.todayPoints
            // Recompute total from the full merged score set (deduped by day).
            var best: [Date: Double] = [:]
            for score in scores {
                let day = cal.startOfDay(for: score.date)
                guard day <= today else { continue }
                best[day] = max(best[day] ?? 0, score.points)
            }
            let totalPts = best.values.reduce(0, +)
            return TodayItem(
                id: item.id, challenge: item.challenge,
                rank: item.rank, participantCount: item.participantCount,
                todayPoints: todayPts, totalPoints: totalPts
            )
        }
    }

    /// Patches `todayPoints` on every active card using the ring data already loaded
    /// from HealthKit — no additional network calls needed. Called at the end of every
    /// `loadChallenges` so all reload triggers (pop-back, push notification, participation
    /// change) always show live activity data instead of potentially-stale CloudKit values.
    ///
    /// Only upgrades a card's today pts; never downgrades (guards against applying a ring
    /// snapshot from earlier in the day when CloudKit already has a more-recent synced value).
    @MainActor
    func patchTodayPointsFromRingData() {
        guard !isLoadingRings, !activeItems.isEmpty else { return }
        let points: Double
        if hasWatch {
            points = PointsCalculator.calculateWatch(
                moveCalories: activeEnergy, moveGoal: moveGoal,
                exerciseMinutes: exerciseMinutes, standHours: standHours
            ).points
        } else {
            points = PointsCalculator.calculateNonWatch(
                steps: steps, stepsGoal: stepsGoal,
                activeEnergy: activeEnergy, activeEnergyGoal: energyGoal,
                exerciseMinutes: exerciseMinutes
            ).points
        }
        guard points > 0 else { return }
        activeItems = activeItems.map { item in
            guard item.todayPoints < points else { return item }  // never downgrade
            // Correct total: swap out the old today value for the new one.
            // Works whether or not CloudKit already included today in the total.
            let adjustedTotal = item.totalPoints - item.todayPoints + points
            return TodayItem(
                id: item.id, challenge: item.challenge,
                rank: item.rank, participantCount: item.participantCount,
                todayPoints: points, totalPoints: max(adjustedTotal, points)
            )
        }
    }

    /// Returns a new TodayItem with the challenge mutated by `modify`, or the original if IDs don't match.
    private func patchItem(_ item: TodayItem, id: String, modify: (inout Challenge) -> Void) -> TodayItem {
        guard item.id == id else { return item }
        var c = item.challenge
        modify(&c)
        return TodayItem(
            id: item.id, challenge: c, rank: item.rank,
            participantCount: item.participantCount,
            todayPoints: item.todayPoints, totalPoints: item.totalPoints
        )
    }

    @MainActor
    private func buildRankedItems(from all: [Challenge], status: ChallengeStatus,
                                  userID: String) async -> (items: [TodayItem], participantIDs: Set<String>) {
        let challenges = all.filter { $0.status == status }
        var items: [TodayItem] = []
        var participantIDs = Set<String>()
        for challenge in challenges {
            do {
                // Fetch participations and scores concurrently — no dependency between them.
                async let partsTask  = ck.fetchParticipations(challengeID: challenge.id)
                async let scoresTask = ck.fetchDailyScores(challengeID: challenge.id)
                var (parts, scores) = try await (partsTask, scoresTask)

                for i in parts.indices {
                    parts[i].dailyScores = scores
                        .filter  { $0.participationID == parts[i].id }
                        .sorted  { $0.date < $1.date }
                }

                let ranked = ScoreAggregator.ranked(parts)
                // Collect every participant's user ID so we can prune stale avatar files.
                participantIDs.formUnion(ranked.map { $0.user.id })

                guard let mine = ranked.first(where: { $0.user.id == userID }) else {
                    // No participation record found for the current user. This can happen
                    // immediately after creating a challenge because CloudKit's query index
                    // hasn't propagated the new Participation record yet.
                    // Show a placeholder card so the challenge doesn't vanish — it will
                    // display correctly on the next refresh once the record is queryable.
                    if challenge.creatorID == userID {
                        items.append(TodayItem(
                            id: challenge.id, challenge: challenge,
                            rank: 1, participantCount: max(1, ranked.count),
                            todayPoints: 0, totalPoints: 0
                        ))
                    }
                    continue
                }

                let todayPts = mine.dailyScores
                    .first(where: { Calendar.current.isDateInToday($0.date) })?.points ?? 0

                items.append(TodayItem(
                    id:               challenge.id,
                    challenge:        challenge,
                    rank:             mine.rank,
                    participantCount: ranked.count,
                    todayPoints:      todayPts,
                    totalPoints:      mine.totalPoints
                ))
            } catch {
                // CloudKit fetch failed for this challenge. Still show a placeholder card
                // for challenges the current user created so they never fully disappear.
                if challenge.creatorID == userID {
                    items.append(TodayItem(
                        id: challenge.id, challenge: challenge,
                        rank: 1, participantCount: 1,
                        todayPoints: 0, totalPoints: 0
                    ))
                }
            }
        }
        return (items, participantIDs)
    }
}

#if DEBUG

enum MockRingPreset: String, CaseIterable {
    case normal = "Normal (<100%)"
    case over   = "Over 100%"
    case empty  = "Empty"
}

extension HomeViewModel {
    @MainActor
    func loadMockData(ringPreset: MockRingPreset = .over) {
        let cal = Calendar.current
        let now = Date()
        func date(_ days: Int) -> Date { cal.date(byAdding: .day, value: days, to: now)! }

        func makeChallenge(_ title: String, status: ChallengeStatus, start: Int, end: Int) -> Challenge {
            Challenge(id: UUID().uuidString, title: title, creatorID: "mock-me",
                      startDate: date(start), endDate: date(end),
                      status: status, inviteCode: "MOCK01",
                      createdAt: now)
        }

        func makeItem(_ c: Challenge, rank: Int, participants: Int, today: Double, total: Double) -> TodayItem {
            TodayItem(id: c.id, challenge: c, rank: rank,
                      participantCount: participants, todayPoints: today, totalPoints: total)
        }

        // Rings
        switch ringPreset {
        case .normal:
            ringData = RingData(moveRingPct: 0.74, exerciseRingPct: 0.60, standRingPct: 0.83,
                                stepsPct: 0.68, activeEnergyPct: 0.74, syncSource: .watch)
        case .over:
            ringData = RingData(moveRingPct: 1.45, exerciseRingPct: 2.0, standRingPct: 1.25,
                                stepsPct: 1.3, activeEnergyPct: 1.45, syncSource: .watch)
        case .empty:
            ringData = RingData(moveRingPct: 0.04, exerciseRingPct: 0.0, standRingPct: 0.08,
                                stepsPct: 0.03, activeEnergyPct: 0.04, syncSource: .watch)
        }
        hasWatch        = true
        activeEnergy    = ringData.moveRingPct    * moveGoal
        exerciseMinutes = ringData.exerciseRingPct * exerciseGoal
        standHours      = ringData.standRingPct   * standGoal
        isLoadingRings  = false

        // Challenges
        let a1 = makeChallenge("Spring Step Challenge", status: .active,    start: -3, end: 4)
        let a2 = makeChallenge("Ring Closers",          status: .active,    start: -1, end: 6)
        let u1 = makeChallenge("Weekend Warrior",       status: .pending,   start:  2, end: 9)
        let u2 = makeChallenge("Office Rivals",         status: .pending,   start:  5, end: 12)
        let c1 = makeChallenge("March Madness",         status: .completed, start: -10, end: -3)

        activeItems         = [makeItem(a1, rank: 1, participants: 5, today: 420,  total: 3_200),
                               makeItem(a2, rank: 3, participants: 8, today: 185,  total: 1_940)]
        completedItems      = [makeItem(c1, rank: 2, participants: 6, today: 0,    total: 8_750)]
        upcomingChallenges  = [u1, u2]
        completedChallenges = [c1]
        allChallenges       = [a1, a2, u1, u2, c1]
        isLoadingChallenges = false
    }
}

#endif
