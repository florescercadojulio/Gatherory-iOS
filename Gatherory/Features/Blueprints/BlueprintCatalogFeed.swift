import Foundation
import Observation

/// The server query identity for one paged Explore surface.
nonisolated struct BlueprintCatalogFeedScope: Hashable, Sendable {
    let category: String?
    let query: String?

    static let all = BlueprintCatalogFeedScope(category: nil, query: nil)

    static func search(_ query: String) -> Self {
        Self(category: nil, query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func category(_ category: BlueprintBrowseCategory) -> Self {
        Self(category: category.rawValue, query: nil)
    }
}

/// One serial cursor stream. Switching a filter invalidates pending responses,
/// so a late page cannot enter another query or category.
@MainActor @Observable
final class BlueprintCatalogFeedModel {
    static let pageSize = 20

    private(set) var scope: BlueprintCatalogFeedScope?
    private(set) var entries: [BlueprintCatalogEntry] = []
    private(set) var availableCategories: [BlueprintBrowseCategory] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var hasLoadedFirstPage = false
    private(set) var loadFailed = false
    private(set) var cursorCycleDetected = false

    private let ownerID: String
    private var generation = UUID()
    private var seenCursors = Set<String>()

    init(ownerID: String) {
        self.ownerID = ownerID
    }

    var isExhausted: Bool {
        hasLoadedFirstPage && nextCursor == nil
    }

    var canLoadMore: Bool {
        !isLoading && !isExhausted
    }

    func activate(_ requestedScope: BlueprintCatalogFeedScope) {
        guard scope != requestedScope else { return }
        generation = UUID()
        scope = requestedScope
        entries = []
        availableCategories = []
        nextCursor = nil
        seenCursors = []
        isLoading = false
        hasLoadedFirstPage = false
        loadFailed = false
        cursorCycleDetected = false
    }

    func refresh(
        fetch: (String?, String?, String?) async throws -> BlueprintCatalogResponse
    ) async {
        guard scope != nil else { return }
        generation = UUID()
        resetStream()
        await loadNextPage(fetch: fetch)
    }

    private func resetStream() {
        entries = []
        availableCategories = []
        nextCursor = nil
        seenCursors = []
        isLoading = false
        hasLoadedFirstPage = false
        loadFailed = false
        cursorCycleDetected = false
    }

    func loadNextPage(
        fetch: (String?, String?, String?) async throws -> BlueprintCatalogResponse
    ) async {
        await loadNextPage(fetch: fetch, staleCursorRestarted: false)
    }

    private func loadNextPage(
        fetch: (String?, String?, String?) async throws -> BlueprintCatalogResponse,
        staleCursorRestarted: Bool
    ) async {
        guard let scope, canLoadMore else { return }
        let token = generation
        let requestedCursor = nextCursor
        isLoading = true
        loadFailed = false
        defer {
            if generation == token { isLoading = false }
        }

        do {
            let response = try await fetch(requestedCursor, scope.category, scope.query)
            guard generation == token, !Task.isCancelled else { return }

            hasLoadedFirstPage = true
            if let categories = response.availableCategories {
                availableCategories = BlueprintBrowseCategory.allCases.filter { categories.contains($0.rawValue) }
            }
            merge(response.entries)
            if response.availableCategories == nil {
                let populated = Set(entries.flatMap(\.browseCategories))
                availableCategories = BlueprintBrowseCategory.allCases.filter { populated.contains($0) }
            }

            let receivedNextCursor = response.nextCursor
            if let receivedNextCursor,
               receivedNextCursor == requestedCursor || seenCursors.contains(receivedNextCursor) {
                // A repeated opaque cursor would otherwise produce an endless
                // sequence of duplicate pages. Stop at the last valid page.
                nextCursor = nil
                cursorCycleDetected = true
            } else {
                nextCursor = receivedNextCursor
                if let requestedCursor { seenCursors.insert(requestedCursor) }
            }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            if requestedCursor != nil, !staleCursorRestarted,
               let failure = error as? CloudSyncFailure,
               case .server("BLUEPRINT_CATALOG_CURSOR_STALE") = failure {
                generation = UUID()
                resetStream()
                await loadNextPage(fetch: fetch, staleCursorRestarted: true)
                return
            }
            loadFailed = true
        }
    }

    private func merge(_ receivedEntries: [BlueprintCatalogEntry]) {
        var indexByCatalogKey = Dictionary(
            uniqueKeysWithValues: entries.enumerated().map { ($0.element.catalogKey, $0.offset) }
        )

        for entry in receivedEntries where entry.definition.supportsCurrentSchema {
            if let index = indexByCatalogKey[entry.catalogKey] {
                if entry.revision > entries[index].revision {
                    entries[index] = entry
                } else if entry.revision == entries[index].revision,
                          entry.contentHash == entries[index].contentHash {
                    entries[index] = entries[index].refreshingDiscoveryMetadata(from: entry)
                }
            } else {
                indexByCatalogKey[entry.catalogKey] = entries.count
                entries.append(entry)
            }
        }
    }
}
