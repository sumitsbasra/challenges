import CoreSpotlight
import UIKit

/// Indexes challenge records into Core Spotlight so they appear in system search results.
///
/// `CSSearchableIndex` handles upserts by `uniqueIdentifier`, so this is safe to call
/// on every app launch or fetch — it won't create duplicate entries.
enum SpotlightIndexer {

    private static let domainIdentifier = "com.challenges.challenges"

    // MARK: - Index

    /// Indexes active and pending challenges. Completed challenges are omitted
    /// to keep search results focused on actionable content.
    static func index(_ challenges: [Challenge]) {
        let items = challenges
            .filter { $0.status == .active || $0.status == .pending }
            .map { searchableItem(for: $0) }

        guard !items.isEmpty else { return }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("[SpotlightIndexer] Indexing failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Remove

    /// Removes all indexed challenge records (call on sign-out).
    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainIdentifier]
        ) { error in
            if let error {
                print("[SpotlightIndexer] Removal failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private static func searchableItem(for challenge: Challenge) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = challenge.title
        attrs.contentDescription = statusDescription(for: challenge)
        attrs.keywords = ["fitness", "challenge", "rings", "competition", challenge.title]
        attrs.startDate = challenge.startDate
        attrs.endDate = challenge.endDate
        attrs.thumbnailData = UIImage(systemName: "trophy.fill")?
            .withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
            .pngData()

        return CSSearchableItem(
            uniqueIdentifier: challenge.id,
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
    }

    private static func statusDescription(for challenge: Challenge) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        switch challenge.status {
        case .active:
            return "Active · ends \(fmt.string(from: challenge.endDate))"
        case .pending:
            return "Starts \(fmt.string(from: challenge.startDate))"
        case .completed:
            return "Completed \(fmt.string(from: challenge.endDate))"
        }
    }
}
