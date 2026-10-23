import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintDiscoveryTests {
    @Test("Explore chooses browse, recent, and live result states")
    func searchModes() {
        #expect(BlueprintSearchMode.resolve(isFocused: false, query: "") == .browse)
        #expect(BlueprintSearchMode.resolve(isFocused: true, query: " \n ") == .recent)
        #expect(BlueprintSearchMode.resolve(isFocused: true, query: "wedding") == .results)
        #expect(BlueprintSearchMode.resolve(isFocused: false, query: "wedding") == .browse)
    }

    @Test("Search finds names, categories, tags, and descriptions without case or accent sensitivity")
    func matching() throws {
        let entry = try catalog().entries[0]
        #expect(entry.browseCategories == [.weddings])
        #expect(entry.matches(query: "  WÉDDING \n ceremony  "))
        #expect(entry.matches(query: "venue visit"))
        #expect(!entry.matches(query: "wedding birthday"))
        #expect(!entry.matches(query: "no such blueprint"))
        var legacy = entry
        legacy.discovery = nil
        #expect(legacy.browseCategories == [.weddings])
        legacy.discovery = .init(categories: ["future"], tags: [], summary: "")
        #expect(legacy.browseCategories == [.events])
    }

    @Test("Browsing history is deduplicated, bounded, durable, and private to the account")
    func recentHistory() throws {
        let suite = "BlueprintDiscoveryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = BlueprintRecentHistory(defaults: defaults)
        for index in 0..<15 { history.record("item\(index)", ownerID: "accountA") }
        history.record("item10", ownerID: "accountA")
        history.record("wedding", ownerID: "accountB")
        #expect(history.keys(ownerID: "accountA").count == 12)
        #expect(history.keys(ownerID: "accountA").first == "item10")
        #expect(history.keys(ownerID: "accountA").filter { $0 == "item10" }.count == 1)
        #expect(history.keys(ownerID: "accountB") == ["wedding"])
        #expect(BlueprintRecentHistory(defaults: defaults).keys(ownerID: "accountA") == history.keys(ownerID: "accountA"))
        history.clear(ownerID: "accountA")
        #expect(history.keys(ownerID: "accountA").isEmpty)
        #expect(history.keys(ownerID: "accountB") == ["wedding"])
        history.record("wedding", ownerID: "")
        #expect(history.keys(ownerID: "").isEmpty)
    }

    @Test("Recents resolve only currently available entries and follow the latest revision")
    func recentCatalogResolution() async throws {
        let suite = "BlueprintDiscoveryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let response = try catalog()
        let entry = response.entries[0]
        let model = BlueprintDiscoveryModel(ownerID: "A", defaults: defaults)
        model.recordAccess(entry)
        #expect(model.recentEntries.isEmpty)
        let newer = BlueprintCatalogEntry(catalogKey: entry.catalogKey, revision: 2, contentHash: entry.contentHash, definition: entry.definition, discovery: entry.discovery)
        await model.load { .init(entries: [newer, entry, newer]) }
        #expect(model.entries.count == 1)
        #expect(model.recentEntries.map(\.revision) == [2])
        let otherAccount = BlueprintDiscoveryModel(ownerID: "B", defaults: defaults)
        await otherAccount.load { response }
        #expect(otherAccount.recentEntries.isEmpty)
        let reloadedAccount = BlueprintDiscoveryModel(ownerID: "A", defaults: defaults)
        await reloadedAccount.load { response }
        #expect(reloadedAccount.recentEntries.map(\.catalogKey) == ["wedding"])
        await model.load { .init(entries: []) }
        #expect(model.recentEntries.isEmpty)
        model.clearRecents()
        #expect(BlueprintRecentHistory(defaults: defaults).keys(ownerID: "A").isEmpty)
    }

    @Test("Equal-revision catalog pages refresh only matching discovery metadata")
    func feedRefreshesMatchingRevisionMetadata() async throws {
        let original = try catalog().entries[0]
        var stale = original
        var staleDiscovery = try #require(stale.discovery)
        staleDiscovery.coverImages = nil
        stale.discovery = staleDiscovery

        let feed = BlueprintCatalogFeedModel(ownerID: "account-a")
        feed.activate(.all)
        await feed.loadNextPage { _, _, _ in
            BlueprintCatalogResponse(entries: [stale], nextCursor: "next")
        }
        await feed.loadNextPage { _, _, _ in
            BlueprintCatalogResponse(entries: [original])
        }
        #expect(feed.entries.first?.discovery?.coverImages?.ideas.isEmpty == false)
        #expect(feed.entries.first?.definition == stale.definition)

        let mismatchedHash = BlueprintCatalogEntry(catalogKey: original.catalogKey, revision: original.revision,
                                                    contentHash: String(repeating: "b", count: 64),
                                                    definition: original.definition, discovery: original.discovery,
                                                    description: original.description, creator: original.creator)
        let guardedFeed = BlueprintCatalogFeedModel(ownerID: "account-a")
        guardedFeed.activate(.all)
        await guardedFeed.loadNextPage { _, _, _ in
            BlueprintCatalogResponse(entries: [stale], nextCursor: "next")
        }
        await guardedFeed.loadNextPage { _, _, _ in
            BlueprintCatalogResponse(entries: [mismatchedHash])
        }
        #expect(guardedFeed.entries.first?.discovery?.coverImages == nil)
        #expect(guardedFeed.entries.first?.contentHash == stale.contentHash)
    }

    @Test("Paged search keeps server-only nested matches and relevance order")
    func pagedSearchPreservesServerResults() async throws {
        let original = try catalog().entries[0]
        let nestedMatch = entry(original, catalogKey: "a-nested", name: "Aardvark Weekend")
        let directMatch = entry(original, catalogKey: "z-direct", name: "Zebra Photography")
        var withoutMetadata = nestedMatch
        withoutMetadata.discovery = .init(categories: [], tags: [], summary: "")
        #expect(!withoutMetadata.matches(query: "photography"))

        let feed = BlueprintCatalogFeedModel(ownerID: "account-a")
        feed.activate(.search("  photography\n"))
        var requestedCursors: [String?] = []
        var requestedQueries: [String?] = []
        await feed.loadNextPage { cursor, category, query in
            requestedCursors.append(cursor)
            requestedQueries.append(query)
            #expect(category == nil)
            return BlueprintCatalogResponse(entries: [directMatch], nextCursor: "page-2")
        }
        await feed.loadNextPage { cursor, category, query in
            requestedCursors.append(cursor)
            requestedQueries.append(query)
            #expect(category == nil)
            return BlueprintCatalogResponse(entries: [withoutMetadata])
        }

        #expect(requestedCursors.count == 2)
        #expect(requestedCursors[0] == nil)
        #expect(requestedCursors[1] == "page-2")
        #expect(requestedQueries == ["photography", "photography"])
        #expect(feed.entries.map(\.catalogKey) == ["z-direct", "a-nested"])
    }

    @Test("A stale continuation restarts the scoped catalog from the server's new first-page order")
    func staleContinuationRestartsFromFirstPage() async throws {
        let original = try catalog().entries[0]
        let oldEntry = entry(original, catalogKey: "old-order", name: "Old Order")
        let firstReplacement = entry(original, catalogKey: "new-order-a", name: "New Order A")
        let secondReplacement = entry(original, catalogKey: "new-order-b", name: "New Order B")
        let feed = BlueprintCatalogFeedModel(ownerID: "account-a")
        feed.activate(.search("  photography "))
        var requestedCursors: [String?] = []
        var requestedQueries: [String?] = []
        let fetch: (String?, String?, String?) async throws -> BlueprintCatalogResponse = { cursor, category, query in
            requestedCursors.append(cursor)
            requestedQueries.append(query)
            #expect(category == nil)
            if requestedCursors.count == 1 {
                return BlueprintCatalogResponse(entries: [oldEntry], nextCursor: "stale-cursor")
            }
            if requestedCursors.count == 2 {
                throw CloudSyncFailure.server("BLUEPRINT_CATALOG_CURSOR_STALE")
            }
            return BlueprintCatalogResponse(entries: [firstReplacement, secondReplacement])
        }
        await feed.loadNextPage(fetch: fetch)
        await feed.loadNextPage(fetch: fetch)

        #expect(requestedCursors == [nil, "stale-cursor", nil])
        #expect(requestedQueries == ["photography", "photography", "photography"])
        #expect(feed.entries.map(\.catalogKey) == ["new-order-a", "new-order-b"])
        #expect(feed.hasLoadedFirstPage && !feed.loadFailed && !feed.isLoading)
    }

    @Test("A failed stale-cursor restart stops after one first-page request")
    func staleCursorRestartFailureDoesNotLoop() async throws {
        let original = try catalog().entries[0]
        let previousPage = entry(original, catalogKey: "old-page", name: "Old Page")
        let feed = BlueprintCatalogFeedModel(ownerID: "account-a")
        feed.activate(.all)
        var requests = 0
        let fetch: (String?, String?, String?) async throws -> BlueprintCatalogResponse = { cursor, _, _ in
            requests += 1
            if cursor == nil, requests == 1 {
                return BlueprintCatalogResponse(entries: [previousPage], nextCursor: "stale-cursor")
            }
            throw CloudSyncFailure.server("BLUEPRINT_CATALOG_CURSOR_STALE")
        }
        await feed.loadNextPage(fetch: fetch)
        await feed.loadNextPage(fetch: fetch)

        #expect(requests == 3)
        #expect(feed.entries.isEmpty)
        #expect(!feed.hasLoadedFirstPage && feed.loadFailed && !feed.isLoading)

        let firstPageFeed = BlueprintCatalogFeedModel(ownerID: "account-a")
        firstPageFeed.activate(.all)
        var firstPageRequests = 0
        await firstPageFeed.loadNextPage { _, _, _ in
            firstPageRequests += 1
            throw CloudSyncFailure.server("BLUEPRINT_CATALOG_CURSOR_STALE")
        }
        #expect(firstPageRequests == 1)
        #expect(firstPageFeed.loadFailed)
    }

    @Test("Changing search scope discards a late response from the stale-cursor restart")
    func scopeChangeDiscardsLateCursorRestart() async throws {
        let original = try catalog().entries[0]
        let oldEntry = entry(original, catalogKey: "old-scope", name: "Old Scope")
        let currentEntry = entry(original, catalogKey: "new-scope", name: "New Scope")
        let feed = BlueprintCatalogFeedModel(ownerID: "account-a")
        feed.activate(.search("old"))
        await feed.loadNextPage { _, _, _ in
            BlueprintCatalogResponse(entries: [oldEntry], nextCursor: "stale-cursor")
        }

        var restartContinuation: CheckedContinuation<BlueprintCatalogResponse, Error>?
        let fetch: (String?, String?, String?) async throws -> BlueprintCatalogResponse = { cursor, _, query in
            if query == "new" {
                #expect(cursor == nil)
                return BlueprintCatalogResponse(entries: [currentEntry])
            }
            if cursor == "stale-cursor" {
                throw CloudSyncFailure.server("BLUEPRINT_CATALOG_CURSOR_STALE")
            }
            return try await withCheckedThrowingContinuation { restartContinuation = $0 }
        }
        let staleRestart = Task { await feed.loadNextPage(fetch: fetch) }
        while restartContinuation == nil { await Task.yield() }

        feed.activate(.search("new"))
        await feed.loadNextPage(fetch: fetch)
        restartContinuation?.resume(returning: BlueprintCatalogResponse(entries: [oldEntry]))
        await staleRestart.value

        #expect(feed.scope == .search("new"))
        #expect(feed.entries.map(\.catalogKey) == ["new-scope"])
        #expect(!feed.loadFailed && !feed.isLoading)
    }

    @Test("Ordinary continuation errors keep the same cursor available for explicit retry")
    func ordinaryContinuationFailureRemainsRetryable() async throws {
        let original = try catalog().entries[0]
        let first = entry(original, catalogKey: "first-page", name: "First Page")
        let second = entry(original, catalogKey: "retried-page", name: "Retried Page")
        let feed = BlueprintCatalogFeedModel(ownerID: "account-a")
        feed.activate(.all)
        var requestedCursors: [String?] = []

        await feed.loadNextPage { cursor, _, _ in
            requestedCursors.append(cursor)
            return BlueprintCatalogResponse(entries: [first], nextCursor: "keep-this-cursor")
        }
        await feed.loadNextPage { cursor, _, _ in
            requestedCursors.append(cursor)
            throw URLError(.notConnectedToInternet)
        }
        #expect(feed.loadFailed)
        await feed.loadNextPage { cursor, _, _ in
            requestedCursors.append(cursor)
            return BlueprintCatalogResponse(entries: [second])
        }

        #expect(requestedCursors == [nil, "keep-this-cursor", "keep-this-cursor"])
        #expect(feed.entries.map(\.catalogKey) == ["first-page", "retried-page"])
        #expect(!feed.loadFailed && !feed.isLoading)
    }

    @Test("A late page from a superseded search cannot enter the active query")
    func supersededSearchPage() async throws {
        let original = try catalog().entries[0]
        let oldResult = entry(original, catalogKey: "old-query", name: "Old Result")
        let currentResult = entry(original, catalogKey: "current-query", name: "Current Result")
        let feed = BlueprintCatalogFeedModel(ownerID: "account-a")
        feed.activate(.search("old"))

        var oldContinuation: CheckedContinuation<BlueprintCatalogResponse, Never>?
        let oldPage = Task {
            await feed.loadNextPage { _, _, _ in
                await withCheckedContinuation { oldContinuation = $0 }
            }
        }
        while oldContinuation == nil { await Task.yield() }

        feed.activate(.search("current"))
        await feed.loadNextPage { cursor, category, query in
            #expect(cursor == nil)
            #expect(category == nil)
            #expect(query == "current")
            return BlueprintCatalogResponse(entries: [currentResult])
        }
        oldContinuation?.resume(returning: BlueprintCatalogResponse(entries: [oldResult]))
        await oldPage.value

        #expect(feed.entries.map(\.catalogKey) == ["current-query"])
        #expect(feed.scope == .search("current"))
    }

    @Test("A failed refresh preserves the last catalog, and retry clears the error")
    func retry() async throws {
        let model = BlueprintDiscoveryModel(ownerID: "")
        let response = try catalog()
        await model.load { throw URLError(.notConnectedToInternet) }
        #expect(model.loadFailed && model.entries.isEmpty && !model.loading)
        await model.load { response }
        #expect(!model.loadFailed && model.entries.count == 1 && !model.loading)
        await model.load { throw URLError(.notConnectedToInternet) }
        #expect(model.loadFailed && model.entries.count == 1 && !model.loading)
    }

    @Test("A superseded catalog response cannot overwrite a newer refresh")
    func staleResponse() async throws {
        let model = BlueprintDiscoveryModel(ownerID: "")
        let response = try catalog()
        var continuation: CheckedContinuation<BlueprintCatalogResponse, Never>?
        let oldLoad = Task {
            await model.load { await withCheckedContinuation { continuation = $0 } }
        }
        while continuation == nil { await Task.yield() }
        await model.load { .init(entries: []) }
        continuation?.resume(returning: response)
        await oldLoad.value
        #expect(model.entries.isEmpty)
        #expect(!model.loading)
    }

    @Test("Canceling an account-bound view prevents its catalog response from publishing")
    func canceledResponse() async throws {
        let model = BlueprintDiscoveryModel(ownerID: "A")
        let response = try catalog()
        var continuation: CheckedContinuation<BlueprintCatalogResponse, Never>?
        let load = Task {
            await model.load { await withCheckedContinuation { continuation = $0 } }
        }
        while continuation == nil { await Task.yield() }
        load.cancel()
        continuation?.resume(returning: response)
        await load.value
        #expect(model.entries.isEmpty)
        #expect(!model.loadFailed && !model.loading)
    }

    private func catalog() throws -> BlueprintCatalogResponse {
        let url = try #require(Bundle(for: DiscoveryFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url))
    }

    private func entry(_ original: BlueprintCatalogEntry, catalogKey: String, name: String) -> BlueprintCatalogEntry {
        let source = original.definition
        let identity = ExperienceBlueprintIdentity(id: catalogKey, revision: source.blueprint.revision, name: name)
        let definition = ExperienceBlueprintDocument(schema: source.schema, kind: source.kind,
            schemaVersion: source.schemaVersion, blueprint: identity, experienceDefaults: source.experienceDefaults,
            roles: source.roles, modules: source.modules, presentation: source.presentation)
        return BlueprintCatalogEntry(catalogKey: catalogKey, revision: original.revision,
            contentHash: original.contentHash, definition: definition,
            discovery: .init(categories: [], tags: [], summary: ""))
    }
}

private final class DiscoveryFixtureBundle: NSObject {}
