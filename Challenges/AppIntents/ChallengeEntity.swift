import AppIntents

// MARK: - ChallengeEntity

/// An AppEntity that represents a Challenge. Used by Siri, Shortcuts,
/// and Apple Intelligence to understand and resolve challenge references.
struct ChallengeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Challenge"
    static var defaultQuery = ChallengeEntityQuery()

    /// Maps 1:1 to Challenge.id (CloudKit recordName UUID string).
    let id: String
    var title: String
    var status: String      // ChallengeStatus.rawValue: "pending" | "active" | "completed"
    var endDate: Date

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(status.capitalized)"
        )
    }
}

extension ChallengeEntity {
    init(challenge: Challenge) {
        self.id = challenge.id
        self.title = challenge.title
        self.status = challenge.status.rawValue
        self.endDate = challenge.endDate
    }
}

// MARK: - ChallengeEntityQuery

/// Resolves ChallengeEntity values by ID or by search string.
/// Siri calls these methods when the user names a specific challenge.
struct ChallengeEntityQuery: EntityQuery, EntityStringQuery {

    // MARK: EntityQuery

    /// Resolves a specific list of known entity IDs — called when Siri already
    /// has an entity reference (e.g. from a donated NSUserActivity).
    func entities(for identifiers: [String]) async throws -> [ChallengeEntity] {
        // No signed-in user (e.g. AppIntents indexing this query at launch before
        // sign-in): return nothing rather than hitting CloudKit with an empty id,
        // which would throw in CKRecord.ID(recordName:) and crash the app.
        let currentUserID = await MainActor.run { UserSession.shared.userID }
        guard let userID = currentUserID, !userID.isEmpty else { return [] }
        let all = try await CloudKitManager.shared.fetchChallenges(forUserID: userID)
        return all
            .filter { identifiers.contains($0.id) }
            .map { ChallengeEntity(challenge: $0) }
    }

    // MARK: EntityStringQuery

    /// Fuzzy name search — called when Siri needs to disambiguate a spoken name
    /// (e.g. "my summer challenge") into a specific entity.
    func entities(matching string: String) async throws -> [ChallengeEntity] {
        // No signed-in user (e.g. AppIntents indexing this query at launch before
        // sign-in): return nothing rather than hitting CloudKit with an empty id,
        // which would throw in CKRecord.ID(recordName:) and crash the app.
        let currentUserID = await MainActor.run { UserSession.shared.userID }
        guard let userID = currentUserID, !userID.isEmpty else { return [] }
        let all = try await CloudKitManager.shared.fetchChallenges(forUserID: userID)
        let lower = string.lowercased()
        return all
            .filter { $0.title.lowercased().contains(lower) }
            .map { ChallengeEntity(challenge: $0) }
    }

    // MARK: Suggested completions

    /// Shown in the Shortcuts app picker and offered as Siri proactive suggestions.
    func suggestedEntities() async throws -> [ChallengeEntity] {
        // No signed-in user (e.g. AppIntents indexing this query at launch before
        // sign-in): return nothing rather than hitting CloudKit with an empty id,
        // which would throw in CKRecord.ID(recordName:) and crash the app.
        let currentUserID = await MainActor.run { UserSession.shared.userID }
        guard let userID = currentUserID, !userID.isEmpty else { return [] }
        let all = try await CloudKitManager.shared.fetchChallenges(forUserID: userID)
        // Prioritise active, then pending; omit completed.
        return all
            .filter { $0.status == .active || $0.status == .pending }
            .map { ChallengeEntity(challenge: $0) }
    }
}
