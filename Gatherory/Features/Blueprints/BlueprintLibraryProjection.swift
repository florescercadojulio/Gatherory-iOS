import Foundation

enum BlueprintLibraryProjection {
    static func hasSetupProgress(_ draft: BlueprintSetupDraft) -> Bool {
        draft.mainDateConfirmed == true || !draft.confirmedDates.isEmpty
    }

    /// Compare the complete saved payload, including catalog and copied definitions.
    /// Sets are normalized before JSON serialization so equivalent selections compare equally.
    static func isExactRecoveryDuplicate(_ draft: BlueprintSetupDraft, of source: BlueprintSetupDraft) -> Bool {
        guard let draftData = canonicalData(for: draft),
              let sourceData = canonicalData(for: source) else { return false }
        return draftData == sourceData
    }

    static func visibleRecoveryDrafts(
        drafts: [BlueprintSetupDraft],
        installations: [BlueprintUsedTemplate],
        ownerID: String
    ) -> [BlueprintSetupDraft] {
        var receiptSources = Set<Data>()
        for installation in installations {
            guard let source = try? installation.previewSource(ownerID: ownerID),
                  let data = canonicalData(for: source) else { continue }
            receiptSources.insert(data)
        }
        return drafts.filter { draft in
            guard let data = canonicalData(for: draft) else { return true }
            return !receiptSources.contains(data)
        }
    }

    private static func canonicalData(for draft: BlueprintSetupDraft) -> Data? {
        do {
            let encoded = try JSONEncoder().encode(draft)
            guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return nil }
            object["selectedChildren"] = draft.selectedChildren.sorted()
            object["selectedIdeas"] = draft.selectedIdeas.sorted()
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            return nil
        }
    }
}
