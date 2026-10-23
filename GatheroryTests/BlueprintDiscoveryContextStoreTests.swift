import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintDiscoveryContextStoreTests {
    @Test("History is bounded, expires after thirty days, and stays account scoped")
    func boundedExpiringAccountScopedHistory() throws {
        let suite = "BlueprintDiscoveryContextStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = BlueprintDiscoveryContextStore(accountID: "account-a", defaults: defaults)
        let token = store.callbackGeneration
        store.recordSeen(catalogKey: "expired", at: now.addingTimeInterval(-BlueprintDiscoveryContextStore.historyLifetime - 1),
                         accountID: "account-a", generation: token)
        for index in 0..<205 {
            store.recordSeen(catalogKey: "key-\(index)", at: now.addingTimeInterval(-Double(204 - index)),
                            accountID: "account-a", generation: token)
        }
        let context = try #require(store.beginOrResumeSession(now: now))
        #expect(context.seen.count == 200)
        #expect(context.seen.allSatisfy { $0.catalogKey != "expired" })
        #expect(context.seen.first?.catalogKey == "key-204")

        let otherAccount = BlueprintDiscoveryContextStore(accountID: "account-b", defaults: defaults)
        #expect(try #require(otherAccount.beginOrResumeSession(now: now)).seen.isEmpty)
    }

    @Test("Session context stays frozen across pages and refresh starts a new snapshot")
    func frozenContextAndExplicitRefresh() throws {
        let suite = "BlueprintDiscoveryContextStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let started = Date(timeIntervalSince1970: 2_000_000_000)
        let store = BlueprintDiscoveryContextStore(accountID: "account-a", defaults: defaults)
        let generation = store.callbackGeneration
        store.recordSeen(catalogKey: "before", at: started.addingTimeInterval(-20),
                         accountID: "account-a", generation: generation)
        let firstPage = try #require(store.beginOrResumeSession(now: started))
        let firstBytes = try firstPage.encodedHeaderValue()
        store.recordSeen(catalogKey: "during", at: started.addingTimeInterval(2),
                         accountID: "account-a", generation: generation)
        let nextPage = try #require(store.beginOrResumeSession(now: started.addingTimeInterval(3)))
        #expect(nextPage == firstPage)
        #expect(try nextPage.encodedHeaderValue() == firstBytes)

        let refreshed = try #require(store.beginOrResumeSession(now: started.addingTimeInterval(4), forceNew: true))
        #expect(refreshed.sessionId != firstPage.sessionId)
        #expect(refreshed.startedAt == started.addingTimeInterval(4))
        #expect(refreshed.seen.contains(where: { $0.catalogKey == "during" }))
    }

    @Test("Meaningful local history records without creating or requiring measurement consent")
    func localHistoryIsIndependentOfMeasurementConsent() throws {
        let suite = "BlueprintDiscoveryContextStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = BlueprintDiscoveryContextStore(accountID: "account-a", defaults: defaults)
        store.recordSeen(catalogKey: "dwelt-card", at: now, accountID: "account-a",
                         generation: store.callbackGeneration)
        #expect(try #require(store.beginOrResumeSession(now: now)).seen.map(\.catalogKey) == ["dwelt-card"])
    }

    @Test("Foreground pagination keeps its session, away expiry renews it, and clock rollback resets future context")
    func foregroundContinuityAwayExpiryAndClockRollback() throws {
        let suite = "BlueprintDiscoveryContextStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = BlueprintDiscoveryContextStore(accountID: "account-a", defaults: defaults)
        let token = store.callbackGeneration
        store.recordSeen(catalogKey: "future", at: now.addingTimeInterval(100), accountID: "account-a", generation: token)
        let initial = try #require(store.beginOrResumeSession(now: now))
        #expect(initial.seen.isEmpty)

        let afterLongForeground = try #require(store.beginOrResumeSession(
            now: now.addingTimeInterval(BlueprintDiscoveryContextStore.sessionIdleLifetime + 60)
        ))
        #expect(afterLongForeground.sessionId == initial.sessionId)

        let awayStart = now.addingTimeInterval(BlueprintDiscoveryContextStore.sessionIdleLifetime + 61)
        store.markAway(now: awayStart)
        let shortReturn = try #require(store.beginOrResumeSession(now: awayStart.addingTimeInterval(60)))
        #expect(shortReturn.sessionId == initial.sessionId)

        let nextAwayStart = awayStart.addingTimeInterval(61)
        store.markAway(now: nextAwayStart)
        let afterLongAway = try #require(store.beginOrResumeSession(
            now: nextAwayStart.addingTimeInterval(BlueprintDiscoveryContextStore.sessionIdleLifetime)
        ))
        #expect(afterLongAway.sessionId != initial.sessionId)

        let rollbackStore = BlueprintDiscoveryContextStore(accountID: "clock-account", defaults: defaults)
        let futureSession = try #require(rollbackStore.beginOrResumeSession(now: now.addingTimeInterval(61)))
        let resetSession = try #require(rollbackStore.beginOrResumeSession(now: now))
        #expect(resetSession.sessionId != futureSession.sessionId)
        #expect(resetSession.startedAt == now)
    }

    @Test("Invalidated account callbacks cannot write into the replacement account")
    func staleCallbackRejected() throws {
        let suite = "BlueprintDiscoveryContextStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = BlueprintDiscoveryContextStore(accountID: "account-a", defaults: defaults)
        let oldToken = old.callbackGeneration
        old.invalidate()
        old.recordSeen(catalogKey: "late", accountID: "account-a", generation: oldToken)
        let replacement = BlueprintDiscoveryContextStore(accountID: "account-b", defaults: defaults)
        #expect(try #require(replacement.beginOrResumeSession()).seen.isEmpty)
        #expect(old.headerValue(for: old.session) == nil)
    }

    @Test("Invalid overlength keys are dropped instead of being truncated into a different identity")
    func rejectsOverlengthCatalogKey() throws {
        let suite = "BlueprintDiscoveryContextStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BlueprintDiscoveryContextStore(accountID: "account-a", defaults: defaults)
        let invalidKey = String(repeating: "k", count: BlueprintDiscoveryContextPolicy.maximumCatalogKeyLength + 1)
        store.recordSeen(catalogKey: invalidKey, accountID: "account-a", generation: store.callbackGeneration)
        #expect(store.liveSeenKeys.isEmpty)
        #expect(try #require(store.beginOrResumeSession()).seen.isEmpty)
        let now = Date.now
        let invalidContext = BlueprintDiscoveryRequestContext(sessionId: UUID(), startedAt: now,
            seen: [.init(catalogKey: invalidKey, lastSeenAt: now)])
        #expect(throws: EncodingError.self) { try invalidContext.encodedHeaderValue() }
    }

    @Test("Frozen context is bounded by the transport header byte limit")
    func headerBytesBounded() throws {
        let suite = "BlueprintDiscoveryContextStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let store = BlueprintDiscoveryContextStore(accountID: "account-a", defaults: defaults)
        let token = store.callbackGeneration
        for index in 0..<200 {
            store.recordSeen(catalogKey: String(repeating: "k", count: 140) + "-\(index)",
                             at: now.addingTimeInterval(-Double(200 - index)),
                             accountID: "account-a", generation: token)
        }
        let context = try #require(store.beginOrResumeSession(now: now))
        #expect(try context.encodedHeaderValue().utf8.count <= BlueprintDiscoveryContextPolicy.headerByteLimit)
        #expect(context.seen.count < 200)
    }

    @Test("A stale browse cursor renews the discovery context before the feed restarts at page one")
    func staleCursorRenewsContextForFeedRestart() async throws {
        let suite = "BlueprintDiscoveryContextStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BlueprintDiscoveryContextStore(accountID: "account-a", defaults: defaults)
        let feed = BlueprintCatalogFeedModel(ownerID: "account-a")
        feed.activate(.all)
        var requestSessionIDs: [UUID] = []
        let fetch: (String?, String?, String?) async throws -> BlueprintCatalogResponse = { cursor, _, _ in
            let requestContext = try #require(store.beginOrResumeSession())
            requestSessionIDs.append(requestContext.sessionId)
            if cursor != nil {
                store.beginOrResumeSession(forceNew: true)
                throw CloudSyncFailure.server("BLUEPRINT_CATALOG_CURSOR_STALE")
            }
            if requestSessionIDs.count == 1 {
                return BlueprintCatalogResponse(entries: [], nextCursor: "stale-cursor")
            }
            return BlueprintCatalogResponse(entries: [])
        }
        await feed.loadNextPage(fetch: fetch)
        await feed.loadNextPage(fetch: fetch)
        let sessions = try #require(requestSessionIDs.count == 3 ? requestSessionIDs : nil)
        #expect(sessions[0] == sessions[1])
        #expect(sessions[2] != sessions[1])
        #expect(feed.hasLoadedFirstPage)
        #expect(!feed.loadFailed)
    }
}
