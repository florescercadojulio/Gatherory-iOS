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
}

private final class DiscoveryFixtureBundle: NSObject {}
