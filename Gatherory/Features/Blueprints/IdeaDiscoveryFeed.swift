import Foundation
import Observation

/// A public, revision-pinned idea shown in Explore. This DTO intentionally has
/// only the published source idea's asset ID and public cover URL. The source
/// identity is required to authorize private media reads for that public idea.
nonisolated struct IdeaDiscoveryEntry: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let sourceBlueprintId: String
    let sourceVersion: Int
    let sourceTitle: String
    let creator: BlueprintCreatorMetadata?
    let idea: BlueprintCatalogIdea
    var coverAssetId: UUID? = nil
    let coverImageURL: String?
}

nonisolated struct IdeaDiscoveryResponse: Decodable, Sendable {
    let ideas: [IdeaDiscoveryEntry]
    let nextCursor: String?
}

@MainActor @Observable
final class IdeaDiscoveryFeedModel {
    static let pageSize = 20
    private(set) var query = ""
    private(set) var ownerID = ""
    private(set) var ideas: [IdeaDiscoveryEntry] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var hasLoadedFirstPage = false
    private(set) var loadFailed = false
    private(set) var cursorCycleDetected = false

    private var generation = UUID()
    private var seenCursors = Set<String>()
    private var didRestartInvalidCursor = false

    var isExhausted: Bool { hasLoadedFirstPage && nextCursor == nil }
    var canLoadMore: Bool { !isLoading && !isExhausted }
    var shouldAutoAdvanceEmptyPage: Bool { ideas.isEmpty && hasLoadedFirstPage && nextCursor != nil && !isLoading }

    func activate(query rawQuery: String, ownerID: String = "") {
        let normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != normalized || self.ownerID != ownerID else { return }
        query = normalized
        self.ownerID = ownerID
        generation = UUID()
        didRestartInvalidCursor = false
        reset()
    }

    func invalidate(ownerID: String) {
        self.ownerID = ownerID
        generation = UUID()
        didRestartInvalidCursor = false
        reset()
    }

    func refresh(fetch: (String?, String?) async throws -> IdeaDiscoveryResponse) async {
        generation = UUID()
        didRestartInvalidCursor = false
        reset()
        await loadNextPage(fetch: fetch)
    }

    func loadNextPage(fetch: (String?, String?) async throws -> IdeaDiscoveryResponse) async {
        await loadNextPage(fetch: fetch, staleCursorRestarted: false)
    }

    private func loadNextPage(
        fetch: (String?, String?) async throws -> IdeaDiscoveryResponse,
        staleCursorRestarted: Bool
    ) async {
        guard canLoadMore else { return }
        let token = generation
        let requestedCursor = nextCursor
        isLoading = true
        loadFailed = false
        defer { if generation == token { isLoading = false } }
        do {
            let response = try await fetch(requestedCursor, query.isEmpty ? nil : query)
            guard generation == token, !Task.isCancelled else { return }
            hasLoadedFirstPage = true
            // Preserve server relevance order while suppressing duplicate rows
            // returned by an overlapping cursor page.
            var ids = Set(ideas.map(\.id))
            ideas.append(contentsOf: response.ideas.filter { ids.insert($0.id).inserted })
            if let cursor = response.nextCursor,
               cursor == requestedCursor || seenCursors.contains(cursor) {
                nextCursor = nil
                cursorCycleDetected = true
            } else {
                nextCursor = response.nextCursor
                if let requestedCursor { seenCursors.insert(requestedCursor) }
            }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            if requestedCursor != nil, !staleCursorRestarted, !didRestartInvalidCursor,
               let failure = error as? CloudSyncFailure,
               case .server("BLUEPRINT_IDEA_CURSOR_INVALID") = failure {
                didRestartInvalidCursor = true
                generation = UUID()
                reset()
                await loadNextPage(fetch: fetch, staleCursorRestarted: true)
                return
            }
            loadFailed = true
        }
    }

    private func reset() {
        ideas = []
        nextCursor = nil
        isLoading = false
        hasLoadedFirstPage = false
        loadFailed = false
        cursorCycleDetected = false
        seenCursors = []
    }
}
