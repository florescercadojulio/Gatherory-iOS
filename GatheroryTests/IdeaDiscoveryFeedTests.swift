import Foundation
import Testing
@testable import Gatherory

@MainActor
struct IdeaDiscoveryFeedTests {
    @Test("Idea feed normalizes query and preserves ranked order across cursor pages")
    func rankedCursorPages() async throws {
        let publishedAssetID = UUID()
        let first = try response(ids: ["rank-1"], next: "next", coverAssetID: publishedAssetID)
        let second = try response(ids: ["rank-1", "rank-2"], next: nil)
        #expect(first.ideas.first?.coverAssetId == publishedAssetID)
        #expect(second.ideas.first?.coverAssetId == nil)
        let feed = IdeaDiscoveryFeedModel()
        feed.activate(query: "  picnic  ")
        var calls: [(String?, String?)] = []
        await feed.loadNextPage { cursor, query in
            calls.append((cursor, query)); return first
        }
        await feed.loadNextPage { cursor, query in
            calls.append((cursor, query)); return second
        }
        #expect(calls.count == 2)
        #expect(calls[0].0 == nil && calls[0].1 == "picnic")
        #expect(calls[1].0 == "next" && calls[1].1 == "picnic")
        #expect(feed.ideas.map(\.id) == ["rank-1", "rank-2"])
        #expect(feed.isExhausted)
    }

    @Test("Idea feed stops repeated cursors and ignores stale query and account responses")
    func cursorAndStaleResponseGuards() async throws {
        let cycle = try response(ids: ["one"], next: "loop")
        let feed = IdeaDiscoveryFeedModel()
        feed.activate(query: "one")
        await feed.loadNextPage { _, _ in cycle }
        await feed.loadNextPage { _, _ in try self.response(ids: ["two"], next: "loop") }
        #expect(feed.cursorCycleDetected)
        #expect(feed.nextCursor == nil)

        feed.activate(query: "old", ownerID: "account-a")
        await feed.refresh { _, _ in
            feed.activate(query: "old", ownerID: "account-b")
            return try self.response(ids: ["stale"], next: nil)
        }
        #expect(feed.ideas.isEmpty)
        #expect(feed.query == "old")
        #expect(feed.ownerID == "account-b")
        #expect(!feed.hasLoadedFirstPage)

        feed.activate(query: "old", ownerID: "account-b")
        await feed.refresh { _, _ in
            feed.activate(query: "new", ownerID: "account-b")
            return try self.response(ids: ["stale-query"], next: nil)
        }
        #expect(feed.query == "new")
        #expect(feed.ideas.isEmpty)
        #expect(!feed.hasLoadedFirstPage)
    }

    @Test("An empty first page can advance, and a failed page can retry")
    func emptyPageAndRetry() async throws {
        let feed = IdeaDiscoveryFeedModel()
        feed.activate(query: "", ownerID: "account-a")
        await feed.loadNextPage { _, _ in try self.response(ids: [], next: "page-2") }
        #expect(feed.hasLoadedFirstPage)
        #expect(feed.ideas.isEmpty)
        #expect(!feed.isExhausted)
        #expect(feed.shouldAutoAdvanceEmptyPage)
        await feed.loadNextPage { cursor, _ in
            #expect(cursor == "page-2")
            return try self.response(ids: ["recovered"], next: nil)
        }
        #expect(feed.ideas.map(\.id) == ["recovered"])
        #expect(!feed.shouldAutoAdvanceEmptyPage)

        let retry = IdeaDiscoveryFeedModel()
        retry.activate(query: "", ownerID: "account-a")
        await retry.loadNextPage { _, _ in throw FeedFailure.expected }
        #expect(retry.loadFailed)
        await retry.loadNextPage { _, _ in try self.response(ids: ["retry-ok"], next: nil) }
        #expect(!retry.loadFailed)
        #expect(retry.ideas.map(\.id) == ["retry-ok"])

        let cancelled = IdeaDiscoveryFeedModel()
        cancelled.activate(query: "", ownerID: "account-a")
        let request = Task { @MainActor in
            await cancelled.loadNextPage { _, _ in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return try self.response(ids: ["cancelled"], next: nil)
            }
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        request.cancel()
        await request.value
        #expect(cancelled.ideas.isEmpty)
        #expect(!cancelled.loadFailed)
    }

    @Test("An invalid idea cursor restarts once from the first page")
    func invalidCursorRestartsOnce() async throws {
        let feed = IdeaDiscoveryFeedModel()
        feed.activate(query: "", ownerID: "account-a")
        var requestedCursors: [String?] = []
        await feed.loadNextPage { cursor, _ in
            requestedCursors.append(cursor)
            return try self.response(ids: ["old-page"], next: "stale-cursor")
        }
        await feed.loadNextPage { cursor, _ in
            requestedCursors.append(cursor)
            if cursor == "stale-cursor" {
                throw CloudSyncFailure.server("BLUEPRINT_IDEA_CURSOR_INVALID")
            }
            return try self.response(ids: ["fresh-page"], next: "fresh-cursor")
        }
        #expect(requestedCursors == [nil, "stale-cursor", nil])
        #expect(feed.ideas.map(\.id) == ["fresh-page"])
        #expect(feed.hasLoadedFirstPage)
        #expect(feed.nextCursor == "fresh-cursor")
        await feed.loadNextPage { cursor, _ in
            requestedCursors.append(cursor)
            throw CloudSyncFailure.server("BLUEPRINT_IDEA_CURSOR_INVALID")
        }
        #expect(requestedCursors == [nil, "stale-cursor", nil, "fresh-cursor"])
        #expect(feed.loadFailed)
        #expect(feed.ideas.map(\.id) == ["fresh-page"])
    }

    private func response(ids: [String], next: String?, coverAssetID: UUID? = nil) throws -> IdeaDiscoveryResponse {
        let ideas: [[String: Any]] = ids.map { id in
            var record: [String: Any] = ["id": id, "sourceBlueprintId": "source", "sourceVersion": 1, "sourceTitle": "Source",
             "idea": ["key": id, "title": "Idea \(id)", "category": "event",
                      "target": ["kind": "main"], "configuration": ["version": 1]] as [String: Any]]
            if let coverAssetID { record["coverAssetId"] = coverAssetID.uuidString }
            return record
        }
        let nextCursor: Any = next.map { $0 as Any } ?? NSNull()
        return try JSONDecoder().decode(IdeaDiscoveryResponse.self,
            from: JSONSerialization.data(withJSONObject: ["ideas": ideas, "nextCursor": nextCursor]))
    }

    private enum FeedFailure: Error { case expected }
}
