import Foundation
import CloudKit
import OSLog

/// Converts between CKRecord and Swift model types.
enum RecordMapper {

    // MARK: - Record type names

    enum RecordType {
        static let user          = "User"
        static let challenge     = "Challenge"
        static let participation = "Participation"
        static let dailyScore    = "DailyScore"
    }

    // MARK: - AppUser

    static func user(from record: CKRecord) -> AppUser? {
        guard
            let displayName = record["displayName"] as? String,
            let appleUserID = record["appleUserID"] as? String,
            let hasWatch    = record["hasAppleWatch"] as? Int
        else {
            Logger.cloudKit.error("RecordMapper.user(from:) failed — record \(record.recordID.recordName, privacy: .public), fields: \(record.allKeys(), privacy: .public)")
            return nil
        }

        let userID = record.recordID.recordName
        var avatarURL: URL? = nil
        if let asset = record["avatarAsset"] as? CKAsset,
           let tmpURL = asset.fileURL,
           let data = try? Data(contentsOf: tmpURL) {
            // Copy from CloudKit's temp directory to our Documents cache so it
            // survives app restarts and iOS temp-file purges.
            AvatarCache.cache(data: data, userID: userID)
            avatarURL = AvatarCache.localURL(for: userID)
        }

        return AppUser(
            id: userID,
            displayName: displayName,
            appleUserID: appleUserID,
            hasAppleWatch: hasWatch == 1,
            avatarURL: avatarURL
        )
    }

    static func record(from user: AppUser) -> CKRecord {
        let recordID = CKRecord.ID(recordName: user.id)
        let record = CKRecord(recordType: RecordType.user, recordID: recordID)
        record["displayName"]   = user.displayName
        record["appleUserID"]   = user.appleUserID
        record["hasAppleWatch"] = user.hasAppleWatch ? 1 : 0
        return record
    }

    // MARK: - Challenge

    static func challenge(from record: CKRecord) -> Challenge? {
        guard
            let title      = record["title"] as? String,
            let creatorRef = record["creatorRef"] as? CKRecord.Reference,
            let startDate  = record["startDate"] as? Date,
            let endDate    = record["endDate"] as? Date,
            let statusStr  = record["status"] as? String,
            let status     = ChallengeStatus(rawValue: statusStr),
            let inviteCode = record["inviteCode"] as? String,
            let createdAt  = record["createdAt"] as? Date
        else {
            Logger.cloudKit.error("RecordMapper.challenge(from:) failed — record \(record.recordID.recordName, privacy: .public), fields: \(record.allKeys(), privacy: .public)")
            return nil
        }

        return Challenge(
            id: record.recordID.recordName,
            title: title,
            creatorID: creatorRef.recordID.recordName,
            startDate: startDate,
            endDate: endDate,
            status: status,
            inviteCode: inviteCode,
            createdAt: createdAt
        )
    }

    static func record(from challenge: Challenge) -> CKRecord {
        let recordID = CKRecord.ID(recordName: challenge.id)
        let record = CKRecord(recordType: RecordType.challenge, recordID: recordID)
        let creatorRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: challenge.creatorID),
                                            action: .none)
        record["title"]            = challenge.title
        record["creatorRef"]       = creatorRef
        record["startDate"]        = challenge.startDate
        record["endDate"]          = challenge.endDate
        record["status"]           = challenge.status.rawValue
        record["inviteCode"]       = challenge.inviteCode
        record["createdAt"]        = challenge.createdAt
        return record
    }

    // MARK: - Participation

    static func participation(from record: CKRecord, user: AppUser) -> Participation? {
        guard
            let challengeRef = record["challengeRef"] as? CKRecord.Reference,
            let joinedAt     = record["joinedAt"] as? Date,
            let statusStr    = record["status"] as? String,
            let status       = ParticipationStatus(rawValue: statusStr),
            let hasWatch     = record["hasAppleWatch"] as? Int
        else {
            Logger.cloudKit.error("RecordMapper.participation(from:) failed — record \(record.recordID.recordName, privacy: .public), fields: \(record.allKeys(), privacy: .public)")
            return nil
        }

        return Participation(
            id: record.recordID.recordName,
            challengeID: challengeRef.recordID.recordName,
            user: user,
            joinedAt: joinedAt,
            status: status,
            hasAppleWatch: hasWatch == 1
        )
    }

    static func record(from participation: Participation) -> CKRecord {
        let recordID = CKRecord.ID(recordName: participation.id)
        let record = CKRecord(recordType: RecordType.participation, recordID: recordID)
        record["challengeRef"] = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: participation.challengeID), action: .none)
        record["userRef"] = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: participation.user.id), action: .none)
        record["joinedAt"]       = participation.joinedAt
        record["status"]         = participation.status.rawValue
        record["hasAppleWatch"]  = participation.hasAppleWatch ? 1 : 0
        // Denormalise the display name onto the participation record so other
        // participants can always show a name even when the Users record is
        // not readable (e.g. restrictive CloudKit security roles or propagation delay).
        record["displayName"]    = participation.user.displayName
        return record
    }

    // MARK: - DailyScore

    static func dailyScore(from record: CKRecord) -> DailyScore? {
        guard
            let participationRef = record["participationRef"] as? CKRecord.Reference,
            let challengeRef     = record["challengeRef"] as? CKRecord.Reference,
            let date             = record["date"] as? Date,
            let points           = record["points"] as? Double,
            let syncSourceStr    = record["syncSource"] as? String,
            let syncSource       = SyncSource(rawValue: syncSourceStr)
        else {
            Logger.cloudKit.error("RecordMapper.dailyScore(from:) failed — record \(record.recordID.recordName, privacy: .public), fields: \(record.allKeys(), privacy: .public)")
            return nil
        }

        let ringData = RingData(
            moveRingPct:      record["moveRingPct"]      as? Double ?? 0,
            exerciseRingPct:  record["exerciseRingPct"]  as? Double ?? 0,
            standRingPct:     record["standRingPct"]     as? Double ?? 0,
            stepsPct:         record["stepsPct"]         as? Double ?? 0,
            activeEnergyPct:  record["activeEnergyPct"]  as? Double ?? 0,
            syncSource:       syncSource,
            moveCalories:     record["moveCalories"]     as? Double ?? 0,
            moveGoal:         record["moveGoal"]         as? Double ?? 700,
            exerciseMinutes:  record["exerciseMinutes"]  as? Double ?? 0,
            exerciseGoal:     record["exerciseGoal"]     as? Double ?? 30,
            standHours:       record["standHours"]       as? Double ?? 0,
            standGoal:        record["standGoal"]        as? Double ?? 12,
            steps:            record["steps"]            as? Double ?? 0,
            stepsGoal:        record["stepsGoal"]        as? Double ?? 10_000,
            activeEnergy:     record["activeEnergy"]     as? Double ?? 0,
            activeEnergyGoal: record["activeEnergyGoal"] as? Double ?? 500,
            totalSteps:       record["totalSteps"]       as? Double ?? 0,
            distanceMeters:   record["distanceMeters"]   as? Double ?? 0
        )

        return DailyScore(
            id: record.recordID.recordName,
            participationID: participationRef.recordID.recordName,
            challengeID: challengeRef.recordID.recordName,
            date: date,
            points: points,
            ringData: ringData,
            lastSyncedAt: record.modificationDate ?? Date()
        )
    }

    static func record(from score: DailyScore) -> CKRecord {
        let recordID = CKRecord.ID(recordName: score.id)
        let record = CKRecord(recordType: RecordType.dailyScore, recordID: recordID)
        record["participationRef"] = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: score.participationID), action: .none)
        record["challengeRef"] = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: score.challengeID), action: .none)
        record["date"]            = score.date
        record["points"]          = score.points
        record["moveRingPct"]      = score.ringData.moveRingPct
        record["exerciseRingPct"]  = score.ringData.exerciseRingPct
        record["standRingPct"]     = score.ringData.standRingPct
        record["stepsPct"]         = score.ringData.stepsPct
        record["activeEnergyPct"]  = score.ringData.activeEnergyPct
        record["syncSource"]       = score.ringData.syncSource.rawValue
        record["moveCalories"]     = score.ringData.moveCalories
        record["moveGoal"]         = score.ringData.moveGoal
        record["exerciseMinutes"]  = score.ringData.exerciseMinutes
        record["exerciseGoal"]     = score.ringData.exerciseGoal
        record["standHours"]       = score.ringData.standHours
        record["standGoal"]        = score.ringData.standGoal
        record["steps"]            = score.ringData.steps
        record["stepsGoal"]        = score.ringData.stepsGoal
        record["activeEnergy"]     = score.ringData.activeEnergy
        record["activeEnergyGoal"] = score.ringData.activeEnergyGoal
        record["totalSteps"]       = score.ringData.totalSteps
        record["distanceMeters"]   = score.ringData.distanceMeters
        return record
    }
}
