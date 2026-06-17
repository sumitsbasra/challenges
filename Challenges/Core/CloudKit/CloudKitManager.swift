import Foundation
import CloudKit

/// Central CloudKit access layer. Wraps the Public Database for all Challenge, Participation,
/// and DailyScore records, and registers CloudKit subscriptions.
final class CloudKitManager: ObservableObject {

    static let shared = CloudKitManager()

    private let container: CKContainer
    private let publicDB: CKDatabase

    // Notification name posted when a CloudKit subscription fires.
    static let subscriptionFiredNotification = Notification.Name("CKSubscriptionFired")

    private init() {
        container = CKContainer(identifier: "iCloud.studio.ssb.challenges")
        publicDB = container.publicCloudDatabase
    }

    // MARK: - iCloud Account

    func fetchCurrentUserRecordID() async throws -> CKRecord.ID {
        try await container.userRecordID()
    }

    // MARK: - User

    func saveUser(_ user: AppUser, avatarData: Data? = nil) async throws {
        // Fetch the existing record if it exists so we have the changeTag.
        // Without it CloudKit rejects subsequent saves with serverRecordChanged.
        let recordID = CKRecord.ID(recordName: user.id)
        let record: CKRecord
        if let existing = try? await publicDB.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: RecordMapper.RecordType.user, recordID: recordID)
        }
        record["displayName"]   = user.displayName
        record["appleUserID"]   = user.appleUserID
        record["hasAppleWatch"] = user.hasAppleWatch ? 1 : 0

        var tmpURL: URL? = nil
        if let data = avatarData {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(user.id)_avatar.jpg")
            try data.write(to: url)
            record["avatarAsset"] = CKAsset(fileURL: url)
            tmpURL = url
        }
        _ = try await publicDB.save(record)
        if let url = tmpURL { try? FileManager.default.removeItem(at: url) }
    }

    func fetchUser(recordName: String) async throws -> AppUser? {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await publicDB.record(for: recordID)
        return RecordMapper.user(from: record)
    }

    // MARK: - Challenge

    func saveChallenge(_ challenge: Challenge) async throws {
        let record = RecordMapper.record(from: challenge)
        _ = try await publicDB.save(record)
    }

    /// Updates a challenge's editable fields in a single round-trip.
    /// Pass nil for any field you don't want to change.
    func updateChallenge(id: String, title: String?, startDate: Date?, endDate: Date?) async throws {
        let recordID = CKRecord.ID(recordName: id)
        let record = try await publicDB.record(for: recordID)
        if let title     { record["title"]     = title }
        if let startDate { record["startDate"] = startDate as CKRecordValue }
        if let endDate   { record["endDate"]   = endDate   as CKRecordValue }
        _ = try await publicDB.save(record)
    }

    /// Updates the challenge status field only (avoids overwriting other fields set remotely).
    ///
    /// Every client that opens the app races to apply lifecycle transitions
    /// (pending→active, active→completed). To avoid redundant writes, this skips the
    /// save when the server record already carries the target status — so only the
    /// first client across the boundary actually writes; the rest no-op.
    func updateChallengeStatus(_ challengeID: String, status: ChallengeStatus) async throws {
        let recordID = CKRecord.ID(recordName: challengeID)
        let record = try await publicDB.record(for: recordID)
        guard (record["status"] as? String) != status.rawValue else { return }
        record["status"] = status.rawValue
        _ = try await publicDB.save(record)
    }

    func fetchChallenge(id: String) async throws -> Challenge? {
        let recordID = CKRecord.ID(recordName: id)
        let record = try await publicDB.record(for: recordID)
        return RecordMapper.challenge(from: record)
    }

    /// Look up a challenge by its 6-char invite code.
    func fetchChallenge(inviteCode: String) async throws -> Challenge {
        // Search by invite code only — no status filter.
        // A challenge transitions pending→active once its start date arrives,
        // so filtering on status="pending" would break joins on/after day 1.
        let predicate = NSPredicate(format: "inviteCode == %@", inviteCode)
        let query = CKQuery(recordType: RecordMapper.RecordType.challenge, predicate: predicate)
        let (matchResults, _) = try await publicDB.records(matching: query, resultsLimit: 1)

        guard let (_, result) = matchResults.first,
              let record = try? result.get(),
              let challenge = RecordMapper.challenge(from: record) else {
            throw CloudKitError.inviteCodeNotFound
        }
        // Completed challenges can't be joined.
        guard challenge.status != .completed else {
            throw CloudKitError.challengeAlreadyCompleted
        }
        return challenge
    }

    /// Fetches all challenges the current user created or joined.
    func fetchChallenges(forUserID userID: String) async throws -> [Challenge] {
        // CKRecord.ID(recordName:) raises an (uncatchable) NSException on an empty
        // string. AppIntents calls this via suggestedEntities()/entities(matching:)
        // during Shortcuts indexing before a user is signed in, so guard explicitly.
        guard !userID.isEmpty else { return [] }
        let userRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: userID), action: .none)
        let createQuery = CKQuery(recordType: RecordMapper.RecordType.challenge,
                                  predicate: NSPredicate(format: "creatorRef == %@", userRef))

        // Run both queries concurrently — no dependency between them.
        async let ownedTask  = fetchAllRecords(matching: createQuery)
        async let joinedTask = fetchJoinedChallenges(userID: userID)
        let (ownedRecords, joinedChallenges) = try await (ownedTask, joinedTask)

        let challenges = ownedRecords.compactMap(RecordMapper.challenge)
        var seen = Set<String>()
        return (challenges + joinedChallenges).filter { seen.insert($0.id).inserted }
    }

    private func fetchJoinedChallenges(userID: String) async throws -> [Challenge] {
        let userRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: userID), action: .none)
        // Include invited and active participations — exclude declined only.
        // Filtering only on "active" caused challenges to vanish from the home feed
        // for participants who were invited but hadn't accepted yet.
        let nonDeclinedStatuses = [ParticipationStatus.active.rawValue,
                                   ParticipationStatus.invited.rawValue]
        let predicate = NSPredicate(format: "userRef == %@ AND status IN %@",
                                   userRef, nonDeclinedStatuses)
        let query = CKQuery(recordType: RecordMapper.RecordType.participation, predicate: predicate)

        let challengeIDs = try await fetchAllRecords(matching: query).compactMap { record -> String? in
            (record["challengeRef"] as? CKRecord.Reference)?.recordID.recordName
        }
        guard !challengeIDs.isEmpty else { return [] }

        let recordIDs = challengeIDs.map { CKRecord.ID(recordName: $0) }
        let fetchResults = try await publicDB.records(for: recordIDs)
        return fetchResults.values.compactMap { result in
            guard let record = try? result.get() else { return nil }
            return RecordMapper.challenge(from: record)
        }
    }

    /// Deletes a challenge and all its participation records.
    /// Only the creator should call this.
    func deleteChallenge(id: String) async throws {
        // Delete participation records first (best-effort; no cascade in CloudKit public DB).
        let challengeRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: id), action: .none)
        let predicate = NSPredicate(format: "challengeRef == %@", challengeRef)
        let query = CKQuery(recordType: RecordMapper.RecordType.participation, predicate: predicate)
        let partRecords = try await fetchAllRecords(matching: query)
        let partIDs = partRecords.map { $0.recordID }

        if !partIDs.isEmpty {
            let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: partIDs)
            op.isAtomic = false
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let e): cont.resume(throwing: e)
                    }
                }
                publicDB.add(op)
            }
        }

        // Delete the challenge record itself.
        try await publicDB.deleteRecord(withID: CKRecord.ID(recordName: id))
    }

    /// Removes the current user's participation from a challenge (leave).
    func leaveChallenge(participationID: String) async throws {
        try await publicDB.deleteRecord(withID: CKRecord.ID(recordName: participationID))
    }

    // MARK: - Participation

    func saveParticipation(_ participation: Participation) async throws {
        let record = RecordMapper.record(from: participation)
        // Use CKModifyRecordsOperation with savePolicy: .allKeys (upsert semantics) instead
        // of publicDB.save(), which uses .ifServerRecordUnchanged. On a retry after a dropped
        // network response the record may already exist on the server with a non-nil changeTag,
        // causing publicDB.save to fail with serverRecordChanged even though the data is ours.
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .allKeys
        operation.isAtomic = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            publicDB.add(operation)
        }
    }

    /// Backfills the `displayName` field on an existing participation record if it
    /// is missing. This lets other participants resolve names without reading the
    /// owner's Users record (which may be restricted by CloudKit security roles).
    /// No-ops silently if the field is already set or the write fails.
    func backfillDisplayNameIfNeeded(participationID: String, displayName: String) async {
        guard let record = try? await publicDB.record(
            for: CKRecord.ID(recordName: participationID)) else { return }
        // Only write if the field is absent or empty — repairs records saved before
        // the join flow was fixed to embed the user's real display name.
        guard (record["displayName"] as? String ?? "").isEmpty else { return }
        record["displayName"] = displayName
        _ = try? await publicDB.save(record)
    }

    /// Fetches all participations for a challenge.
    ///
    /// Uses a two-step approach to avoid an N+1 query:
    /// 1. Fetch all Participation records in one query (paginated).
    /// 2. Collect every referenced user ID, then batch-fetch all Users in one call.
    ///
    /// Result: exactly 2 network round trips regardless of group size.
    func fetchParticipations(challengeID: String) async throws -> [Participation] {
        let challengeRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: challengeID), action: .none)
        let predicate = NSPredicate(format: "challengeRef == %@", challengeRef)
        let query = CKQuery(recordType: RecordMapper.RecordType.participation, predicate: predicate)

        // Step 1: fetch all participation records (handles pagination).
        let partRecords = try await fetchAllRecords(matching: query)

        // Step 2: collect unique user record IDs.
        let userRecordIDs: [CKRecord.ID] = partRecords.compactMap { record in
            (record["userRef"] as? CKRecord.Reference)?.recordID
        }
        guard !userRecordIDs.isEmpty else { return [] }

        // Step 3: batch-fetch all users in ONE round trip.
        let userResults = try await publicDB.records(for: userRecordIDs)
        let usersByID: [String: AppUser] = userResults.reduce(into: [:]) { dict, pair in
            let (recordID, result) = pair
            if let record = try? result.get(),
               let user = RecordMapper.user(from: record) {
                dict[recordID.recordName] = user
            }
        }

        // Step 4: for any user IDs missing from the batch (race condition / propagation
        // delay), attempt individual fetches so we never fall back to "Participant".
        let missingIDs = Set(partRecords.compactMap {
            ($0["userRef"] as? CKRecord.Reference)?.recordID.recordName
        }).subtracting(usersByID.keys)

        var allUsers = usersByID
        await withTaskGroup(of: (String, AppUser?).self) { group in
            for id in missingIDs {
                group.addTask {
                    let rid = CKRecord.ID(recordName: id)
                    let fetched = try? await self.publicDB.record(for: rid)
                    let user = fetched.flatMap { RecordMapper.user(from: $0) }
                    return (id, user)
                }
            }
            for await (id, user) in group {
                if let user { allUsers[id] = user }
            }
        }

        // Step 5: assemble Participation values using the completed lookup.
        // Fallback priority:
        //   a) Full AppUser from the Users record (preferred)
        //   b) Display name embedded on the Participation record itself (resilient to
        //      restrictive CloudKit security roles on Users — written at join/create time)
        //   c) Current user's own session data
        //   d) Generic placeholder — should never be reached after (b) is populated
        return partRecords.compactMap { record -> Participation? in
            guard let userRef = record["userRef"] as? CKRecord.Reference else { return nil }
            let userID = userRef.recordID.recordName

            if let fullUser = allUsers[userID] {
                return RecordMapper.participation(from: record, user: fullUser)
            }

            // Build a lightweight user from the denormalised displayName field on
            // the participation record — avoids cross-user record reads entirely.
            let embeddedName = record["displayName"] as? String
            let fallbackName: String
            if let name = embeddedName, !name.isEmpty {
                fallbackName = name
            } else if UserSession.shared.currentUser?.id == userID {
                fallbackName = UserSession.shared.currentUser?.displayName ?? "Me"
            } else {
                fallbackName = "..."
            }
            let fallbackUser = AppUser(
                id: userID,
                displayName: fallbackName,
                appleUserID: "",
                hasAppleWatch: (record["hasAppleWatch"] as? Int) == 1
            )
            return RecordMapper.participation(from: record, user: fallbackUser)
        }
    }

    // MARK: - DailyScore

    /// Batch-upsert daily scores. Uses `savePolicy: .changedKeys` so deterministic recordNames
    /// make every write an update, never a duplicate.
    func saveDailyScores(_ scores: [DailyScore]) async throws {
        guard !scores.isEmpty else { return }
        let records = scores.map { RecordMapper.record(from: $0) }
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.isAtomic = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            publicDB.add(operation)
        }
    }

    func fetchDailyScores(challengeID: String) async throws -> [DailyScore] {
        let challengeRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: challengeID), action: .none)
        let predicate = NSPredicate(format: "challengeRef == %@", challengeRef)
        let query = CKQuery(recordType: RecordMapper.RecordType.dailyScore, predicate: predicate)
        return try await fetchAllRecords(matching: query).compactMap(RecordMapper.dailyScore)
    }

    func fetchDailyScores(participationID: String) async throws -> [DailyScore] {
        let partRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: participationID), action: .none)
        let predicate = NSPredicate(format: "participationRef == %@", partRef)
        let query = CKQuery(recordType: RecordMapper.RecordType.dailyScore, predicate: predicate)
        return try await fetchAllRecords(matching: query).compactMap(RecordMapper.dailyScore)
    }

    func fetchDailyScores(challengeID: String, since date: Date) async throws -> [DailyScore] {
        let challengeRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: challengeID), action: .none)
        let predicate = NSPredicate(format: "challengeRef == %@ AND modificationDate > %@",
                                   challengeRef, date as CVarArg)
        let query = CKQuery(recordType: RecordMapper.RecordType.dailyScore, predicate: predicate)
        return try await fetchAllRecords(matching: query).compactMap(RecordMapper.dailyScore)
    }

    // MARK: - Retry Helper

    /// Runs a CloudKit operation with bounded retry on transient errors so a single
    /// hiccup (rate limiting, a busy zone, a brief service/network blip) doesn't surface
    /// as a "Couldn't load" banner. Honors the server's `retryAfterSeconds` hint.
    private func withRetry<T>(maxAttempts: Int = 3, _ operation: () async throws -> T) async throws -> T {
        let retryable: Set<CKError.Code> = [
            .networkUnavailable, .networkFailure, .serviceUnavailable,
            .requestRateLimited, .zoneBusy, .serverResponseLost,
        ]
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                let ckError = error as? CKError
                guard let code = ckError?.code, retryable.contains(code), attempt < maxAttempts else {
                    #if DEBUG
                    print("[CloudKitManager] read failed (attempt \(attempt)): \((error as? CKError)?.code.rawValue as Any) \(error.localizedDescription)")
                    #endif
                    throw error
                }
                let delay = ckError?.retryAfterSeconds ?? Double(attempt)  // linear backoff fallback
                #if DEBUG
                print("[CloudKitManager] retryable error \(code) — retrying in \(delay)s (attempt \(attempt + 1)/\(maxAttempts))")
                #endif
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }

    // MARK: - Pagination Helper

    /// Fetches every record matching `query`, following CloudKit cursors until exhausted.
    ///
    /// CloudKit returns results in pages (server default ~200 records). Callers that
    /// discard the cursor silently lose records beyond the first page. This helper
    /// keeps fetching until `queryCursor` is nil, guaranteeing complete results.
    private func fetchAllRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []

        let (initial, initialCursor) = try await withRetry { try await self.publicDB.records(matching: query) }
        records += initial.compactMap { try? $1.get() }

        var cursor = initialCursor
        while let activeCursor = cursor {
            let (more, nextCursor) = try await withRetry { try await self.publicDB.records(continuingMatchFrom: activeCursor) }
            records += more.compactMap { try? $1.get() }
            cursor = nextCursor
        }

        return records
    }

    // MARK: - CloudKit Subscriptions

    func registerSubscriptions(forActiveChallengeIDs challengeIDs: [String]) async {
        guard !challengeIDs.isEmpty else { return }

        // Subscription 1: DailyScore updates for active challenges (leaderboard refresh)
        let challengeRefs = challengeIDs.map {
            CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none)
        }
        let scorePredicate = NSPredicate(format: "challengeRef IN %@", challengeRefs)
        let scoreSubscription = CKQuerySubscription(
            recordType: RecordMapper.RecordType.dailyScore,
            predicate: scorePredicate,
            subscriptionID: "active-daily-scores",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        scoreSubscription.notificationInfo = makeNotificationInfo()

        // Subscription 2: Participation changes for the current user.
        // If we can't resolve the current user ID, abort rather than poisoning
        // the subscription predicate with an empty string.
        let currentUserID: String
        do {
            currentUserID = try await fetchCurrentUserRecordID().recordName
        } catch {
            #if DEBUG
            print("[CloudKitManager] registerSubscriptions: failed to fetch current user ID — \(error). Skipping participation subscription.")
            #endif
            return
        }
        let userRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: currentUserID), action: .none)
        let participationPredicate = NSPredicate(format: "userRef == %@", userRef)
        let participationSubscription = CKQuerySubscription(
            recordType: RecordMapper.RecordType.participation,
            predicate: participationPredicate,
            subscriptionID: "user-participations",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        participationSubscription.notificationInfo = makeNotificationInfo()

        await registerSubscriptionsWithRetry(
            subscriptions: [scoreSubscription, participationSubscription],
            attempt: 1
        )
    }

    private func registerSubscriptionsWithRetry(subscriptions: [CKSubscription], attempt: Int) async {
        let maxAttempts = 3
        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: subscriptions,
            subscriptionIDsToDelete: nil
        )
        operation.qualityOfService = .utility

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                operation.modifySubscriptionsResultBlock = { result in
                    switch result {
                    case .success:
                        cont.resume()
                    case .failure(let error):
                        cont.resume(throwing: error)
                    }
                }
                publicDB.add(operation)
            }
        } catch {
            let ckError = error as? CKError
            let retryDelay = ckError?.retryAfterSeconds ?? 5.0
            let isRetryable = ckError?.code == .networkUnavailable
                || ckError?.code == .networkFailure
                || ckError?.code == .serviceUnavailable
                || ckError?.code == .requestRateLimited

            #if DEBUG
            print("[CloudKitManager] registerSubscriptions attempt \(attempt) failed: \(error)")
            #endif

            if isRetryable && attempt < maxAttempts {
                #if DEBUG
                print("[CloudKitManager] Retrying subscription registration in \(retryDelay)s (attempt \(attempt + 1)/\(maxAttempts))")
                #endif
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                await registerSubscriptionsWithRetry(subscriptions: subscriptions, attempt: attempt + 1)
            } else {
                #if DEBUG
                print("[CloudKitManager] registerSubscriptions failed after \(attempt) attempt(s): \(error)")
                #endif
            }
        }
    }

    private func makeNotificationInfo() -> CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true  // silent push
        return info
    }
}

