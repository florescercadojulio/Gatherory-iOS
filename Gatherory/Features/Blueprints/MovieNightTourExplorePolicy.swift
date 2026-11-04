import Foundation

enum MovieNightTourExplorePolicy {
    static let catalogKey = "movie_night"

    static func bundledEntry(bundle: Bundle = .main) -> BlueprintCatalogEntry? {
        guard let url = bundle.url(forResource: "movie-night-blueprint.v1", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return decodeBundledEntry(data)
    }

    static func decodeBundledEntry(_ data: Data) -> BlueprintCatalogEntry? {
        guard var entry = try? JSONDecoder().decode(BlueprintCatalogEntry.self, from: data),
              entry.catalogKey == catalogKey,
              entry.revision == 1,
              entry.definition.blueprint.id == catalogKey,
              entry.definition.blueprint.revision == 1 else { return nil }
        entry.creator = BlueprintCreatorMetadata(displayName: "Gatherory")
        return entry
    }

    /// Keeps the bundled card first and removes catalog copies of it and any
    /// duplicate catalog keys, preserving the feed's remaining order.
    static func merge(bundled: BlueprintCatalogEntry?, catalogEntries: [BlueprintCatalogEntry]) -> [BlueprintCatalogEntry] {
        var seenKeys = Set<String>()
        var result: [BlueprintCatalogEntry] = []
        if let bundled {
            seenKeys.insert(bundled.catalogKey)
            result.append(bundled)
        }
        for entry in catalogEntries
        where entry.catalogKey != catalogKey && seenKeys.insert(entry.catalogKey).inserted {
            result.append(entry)
        }
        return result
    }

    static func isSelectable(catalogKey: String, guidedTourActive: Bool, guidedSelectionKey: String?) -> Bool {
        guard guidedTourActive else { return true }
        guard let guidedSelectionKey else { return false }
        return catalogKey == guidedSelectionKey
    }
}
