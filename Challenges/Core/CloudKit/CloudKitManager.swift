import Foundation
import CloudKit

/// Central CloudKit access layer. Wraps the Public Database for all Challenge, Participation,
/// and DailyScore records, and registers CloudKit subscriptions.
@MainActor
final class CloudKitManager: ObservableObject {

    static let shared = CloudKitManager()

    private let container: CKContainer
    private let publicDB: CKDatabase

    // Notification name posted when a CloudKit subscription fires.
    static let subscriptionFiredNotification = Notification.Name("CKSubscriptionFired")

    private init() {
        container = CKContainer(identifier: "iCloud.com.yourname.challenges")
        publicDB = container.publicCloudDatabase
    }

    // MARK: - iCloud Account

    func fetchCurrentUserRecordID() async throws -> CKRecord.ID {
        try await container.userRecordID()
    }

    // MARK: - User

    func saveUser(_ user: AppUser) async throws {
        let record = RecordMapper.record(from: user)
        _ = try await publicDB.save(record)
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

    /// Updates the challenge status field only (avoids overwriting other fields set remotely).
    func updateChallengeStatus(_ challengeID: String, status: ChallengeStatus) async throws {
        let recordID = CKRecord.ID(recordName: challengeID)
        let record = try await publicDB.record(for: recordID)
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
        let predicate = NSPredicate(format: "inviteCode == %@ AND status == %@",
                                   inviteCode, ChallengeStatus.pending.rawValue)
        let query = CKQuery(recordType: RecordMapper.RecordType.challenge, predicate: predicate)
        let (matchResults, _) = try await publicDB.records(matching: query, resultsLimit: 1)

        guard let (_, result) = matchResults.first,
              let record = try? result.get(),
              let challenge = RecordMapper.challenge(from: record) else {
            throw CloudKitError.inviteCodeNotFound
        }
        return challenge
    }

    /// Fetches all active and pending challenges the current user participates in.
    func fetchChallenges(forUserID userID: String) async throws -> [Challenge] {
        let userRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: userID), action: .none)
        let createdPredicate = NSPredicate(format: "creatorRef == %@", userRef)

        // Fetch challenges created by the user.
        let createQuery = CKQuery(recordType: RecordMapper.RecordType.challenge, predicate: createdPredicate)
        let (matchResults, _) = try await publicDB.records(matching: createQuery)
        let challenges = matchResults.compactMap { _, result in
            try? result.get()
        }.compactMap { RecordMapper.challenge(from: $0) }

        // Fetch challenges the user has joined via Participation records.
        let joinedChallenges = try await fetchJoinedChallenges(userID: userID)

        // Deduplicate by id.
        var seen = Set<String>()
        return (challenges + joinedChallenges).filter { seen.insert($0.id).inserted }
    }

    private func fetchJoinedChallenges(userID: String) async throws -> [Challenge] {
        let userRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: userID), action: .none)
        let predicate = NSPredicate(format: "userRef == %@ AND status == %@",
                                   userRef, ParticipationStatus.active.rawValue)
        let query = CKQuery(recordType: RecordMapper.RecordType.participation, predicate: predicate)
        let (matchResults, _) = try await publicDB.records(matching: query)

        let challengeIDs = matchResults.compactMap { _, result -> String? in
            guard let record = try? result.get(),
                  let ref = record["challengeRef"] as? CKRecord.Reference else { return nil }
            return ref.recordID.recordName
        }

        let recordIDs = challengeIDs.map { CKRecord.ID(recordName: $0) }
        let fetchResults = try await publicDB.records(for: recordIDs)
        return fetchResults.values.compactMap { result in
            guard let record = try? result.get() else { return nil }
            return RecordMapper.challenge(from: record)
        }
    }

    // MARK: - Participation

    func saveParticipation(_ participation: Participation) async throws {
        let record = RecordMapper.record(from: participation)
        _ = try await publicDB.save(record)
    }

    func fetchParticipations(challengeID: String) async throws -> [Participation] {
        let challengeRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: challengeID), action: .none)
        let predicate = NSPredicate(format: "challengeRef == %@", challengeRef)
        let query = CKQuery(recordType: RecordMapper.RecordType.participation, predicate: predicate)
        let (matchResults, _) = try await publicDB.records(matching: query)

        var participations: [Participation] = []
        for (_, result) in matchResults {
            guard let record = try? result.get(),
                  let userRef = record["userRef"] as? CKRecord.Reference,
                  let user = try? await fetchUser(recordName: userRef.recordID.recordName),
                  let participation = RecordMapper.participation(from: record, user: user)
            else { continue }
            participations.append(participation)
        }
        return participations
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
        let (matchResults, _) = try await publicDB.records(matching: query)

        return matchResults.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return RecordMapper.dailyScore(from: record)
        }
    }

    func fetchDailyScores(challengeID: String, since date: Date) async throws -> [DailyScore] {
        let challengeRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: challengeID), action: .none)
        let predicate = NSPredicate(format: "challengeRef == %@ AND modificationDate > %@",
                                   challengeRef, date as CVarArg)
        let query = CKQuery(recordType: RecordMapper.RecordType.dailyScore, predicate: predicate)
        let (matchResults, _) = try await publicDB.records(matching: query)

        return matchResults.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return RecordMapper.dailyScore(from: record)
        }
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

        // Subscription 2: Participation changes for the current user
        let currentUserID = (try? await fetchCurrentUserRecordID().recordName) ?? ""
        let userRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: currentUserID), action: .none)
        let participationPredicate = NSPredicate(format: "userRef == %@", userRef)
        let participationSubscription = CKQuerySubscription(
            recordType: RecordMapper.RecordType.participation,
            predicate: participationPredicate,
            subscriptionID: "user-participations",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        participationSubscription.notificationInfo = makeNotificationInfo()

        let operation = CKModifySubscriptionsOperation(
            subscriptionsToSave: [scoreSubscription, participationSubscription],
            subscriptionIDsToDelete: nil
        )
        operation.qualityOfService = .utility
        publicDB.add(operation)
    }

    private func makeNotificationInfo() -> CKSubscription.NotificationInfo {
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true  // silent push
        return info
    }
}
