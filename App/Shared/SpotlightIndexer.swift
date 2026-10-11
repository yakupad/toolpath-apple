import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Keeps Spotlight in sync with the job list so a file can be found by name
/// from system search. Only names and cached summary numbers are indexed —
/// never the G-code text itself. The index stays on this device.
enum SpotlightIndexer {
    static let domain = "com.yakupad.toolpath.jobs"

    struct Entry: Sendable, Hashable {
        let id: UUID
        let name: String
        let score: Int
        let minutes: Double
        let isAnalyzed: Bool
    }

    static func sync(_ entries: [Entry]) async {
        let items = entries.map { entry in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = entry.name
            attributes.displayName = entry.name
            if entry.isAnalyzed {
                let minutes = Int(entry.minutes.rounded())
                attributes.contentDescription = String(localized: "Safety score \(entry.score) · about \(minutes) min")
            }
            attributes.keywords = ["G-code", "CNC", (entry.name as NSString).pathExtension]
            return CSSearchableItem(uniqueIdentifier: entry.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        }
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        guard !items.isEmpty else { return }
        try? await index.indexSearchableItems(items)
    }

    /// The job id from a Spotlight continuation, if this activity came from one.
    static func jobID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}
