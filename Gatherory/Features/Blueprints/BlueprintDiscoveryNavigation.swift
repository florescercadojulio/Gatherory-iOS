import Foundation

/// Each catalog surface has a distinct source, even when it shows the same entry.
enum BlueprintCatalogSource: Hashable {
    case results
    case recent
    case category(String)
}

struct BlueprintPreviewTransitionID: Hashable {
    let source: BlueprintCatalogSource
    let entryID: String
}

struct BlueprintPreviewSelection: Identifiable, Hashable {
    let entry: BlueprintCatalogEntry
    let source: BlueprintCatalogSource
    var id: BlueprintPreviewTransitionID { .init(source: source, entryID: entry.id) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Navigation-local snapshots keep the zoom source mounted when pushing a
/// preview dismisses search focus or records/reorders recent history.
/// This is not a catalog grant, persisted draft or installation intent.
struct BlueprintDiscoveryNavigation {
    var selection: BlueprintPreviewSelection?
    private var retainedMode: BlueprintSearchMode?
    private var retainedSource: BlueprintCatalogSource?
    private var retainedEntries: [BlueprintCatalogEntry] = []
    private(set) var retainedQuery: String?

    func mode(isFocused: Bool, query: String) -> BlueprintSearchMode {
        retainedMode ?? .resolve(isFocused: isFocused, query: query)
    }

    func entries(for source: BlueprintCatalogSource, fallback: [BlueprintCatalogEntry]) -> [BlueprintCatalogEntry] {
        retainedSource == source ? retainedEntries : fallback
    }

    var restoresSearchFocus: Bool {
        switch retainedSource {
        case .results?, .recent?: true
        default: false
        }
    }

    mutating func open(_ entry: BlueprintCatalogEntry, from source: BlueprintCatalogSource,
                       entries: [BlueprintCatalogEntry], mode: BlueprintSearchMode, query: String) {
        retainedMode = mode
        retainedSource = source
        retainedEntries = entries
        retainedQuery = query
        selection = .init(entry: entry, source: source)
    }

    mutating func completeReturn() {
        guard selection == nil else { return }
        retainedMode = nil
        retainedSource = nil
        retainedEntries = []
        retainedQuery = nil
    }
}
