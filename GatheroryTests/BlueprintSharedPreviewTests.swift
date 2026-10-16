import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintSharedPreviewTests {
    private let token = String(repeating: "a1", count: 32)

    @Test("Opening a shared link resolves its pinned entry without creating a draft or reading a public catalog")
    func resolvesBeforeSetup() async throws {
        let entry = try fixture()
        let model = BlueprintSharedPreviewModel()
        var fetched = 0
        var savedReads = 0
        await model.load(ownerID: "A", token: token, pendingInstallation: { false }, savedDraft: {
            savedReads += 1
            return nil
        }, fetch: {
            fetched += 1
            return entry
        })
        #expect(model.entry?.catalogKey == entry.catalogKey)
        #expect(model.entry?.revision == entry.revision)
        #expect(model.entry?.contentHash == entry.contentHash)
        #expect(fetched == 1 && savedReads == 0)
        #expect(!model.isLoading && !model.usesSavedPreview && model.errorMessage == nil)
    }

    @Test("Offline preview reads the existing account/link draft without changing selections, UUID or confirmed dates")
    func offlineDraftIsReadOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = BlueprintSetupDraftStore(directoryURL: directory)
        let draft = try savedDraft()
        try drafts.save(draft)
        let model = BlueprintSharedPreviewModel()
        await model.load(ownerID: "A", token: token, pendingInstallation: { false }, savedDraft: {
            try drafts.load(ownerUserID: "A", shareToken: token)
        }, fetch: { throw URLError(.notConnectedToInternet) })

        #expect(model.entry?.contentHash == draft.entry.contentHash)
        #expect(model.usesSavedPreview && model.errorMessage == nil)
        let loaded = try drafts.load(ownerUserID: "A", shareToken: token)
        let unchanged = try #require(loaded)
        #expect(unchanged.requestID == draft.requestID)
        #expect(unchanged.selectedChildren == draft.selectedChildren)
        #expect(unchanged.selectedIdeas == draft.selectedIdeas)
        #expect(unchanged.confirmedDates == draft.confirmedDates)
        #expect(unchanged.startsAt == draft.startsAt)
        #expect(unchanged.timeZoneIdentifier == draft.timeZoneIdentifier)
        #expect(try drafts.all(ownerUserID: "A").count == 1)
        #expect(try drafts.all(ownerUserID: "B").isEmpty)
    }

    @Test("Fresh offline links do not manufacture content or a setup draft")
    func noOfflineDraft() async {
        let model = BlueprintSharedPreviewModel()
        await model.load(ownerID: "A", token: token, pendingInstallation: { false }, savedDraft: { nil }, fetch: {
            throw URLError(.notConnectedToInternet)
        })
        #expect(model.entry == nil && !model.usesSavedPreview)
        #expect(model.errorMessage == BlueprintCopy.loadFailed)
    }

    @Test("Revocation, auth failures, invalid responses and TLS failures never fall back to cached content")
    func authoritativeDenialIsNotOffline() async throws {
        let draft = try savedDraft()
        let failures: [Error] = [
            CloudSyncFailure.server("BLUEPRINT_LINK_UNAVAILABLE"),
            CloudSyncFailure.server("BLUEPRINT_NOT_FOUND"),
            CloudSyncFailure.server("HTTP_404"),
            CloudSyncFailure.forbidden(nil),
            CloudSyncFailure.invalidSession,
            CloudSyncFailure.invalidResponse,
            CloudSyncFailure.server("HTTP_500"),
            URLError(.serverCertificateUntrusted),
            URLError(.badServerResponse),
        ]
        for failure in failures {
            let model = BlueprintSharedPreviewModel()
            var savedReads = 0
            await model.load(ownerID: "A", token: token, pendingInstallation: { false }, savedDraft: {
                savedReads += 1
                return draft
            }, fetch: { throw failure })
            #expect(model.entry == nil && !model.usesSavedPreview)
            #expect(model.errorMessage != nil && savedReads == 0)
        }
    }

    @Test("Offline fallback cannot cross an account or a link boundary")
    func cacheIsolation() async throws {
        let draft = try savedDraft()
        var wrongAccount = draft
        wrongAccount.ownerUserID = "B"
        var wrongLink = draft
        wrongLink.shareToken = String(repeating: "b2", count: 32)
        for invalid in [wrongAccount, wrongLink] {
            let model = BlueprintSharedPreviewModel()
            await model.load(ownerID: "A", token: token, pendingInstallation: { false }, savedDraft: { invalid }, fetch: {
                throw URLError(.networkConnectionLost)
            })
            #expect(model.entry == nil && !model.usesSavedPreview)
        }
    }

    @Test("Superseded account/link callbacks cannot replace the current preview or expose an old cached draft")
    func supersededResolution() async throws {
        let entry = try fixture()
        let model = BlueprintSharedPreviewModel()
        var continuation: CheckedContinuation<BlueprintCatalogEntry, Error>?
        var savedReads = 0
        let old = Task {
            await model.load(ownerID: "A", token: token, pendingInstallation: { false }, savedDraft: {
                savedReads += 1
                return nil
            }, fetch: { try await withCheckedThrowingContinuation { continuation = $0 } })
        }
        while continuation == nil { await Task.yield() }
        await model.load(ownerID: "B", token: String(repeating: "b2", count: 32), pendingInstallation: { false }, savedDraft: { nil }, fetch: {
            throw CloudSyncFailure.server("BLUEPRINT_LINK_UNAVAILABLE")
        })
        continuation?.resume(returning: entry)
        await old.value
        #expect(model.entry == nil && !model.isLoading)
        #expect(model.errorMessage == BlueprintCopy.sharedLinkUnavailable)
        #expect(savedReads == 0)
    }

    @Test("Canceling a link resolution prevents late content from being published")
    func cancellation() async throws {
        let entry = try fixture()
        let model = BlueprintSharedPreviewModel()
        var continuation: CheckedContinuation<BlueprintCatalogEntry, Never>?
        let load = Task {
            await model.load(ownerID: "A", token: token, pendingInstallation: { false }, savedDraft: { nil }, fetch: {
                await withCheckedContinuation { continuation = $0 }
            })
        }
        while continuation == nil { await Task.yield() }
        load.cancel()
        continuation?.resume(returning: entry)
        await load.value
        #expect(model.entry == nil)
    }

    @Test("A revoked link still exposes pending receipt recovery, without exposing its template")
    func pendingRecoverySurvivesRevocation() async {
        let model = BlueprintSharedPreviewModel()
        await model.load(ownerID: "A", token: token, pendingInstallation: { true }, savedDraft: { nil }, fetch: {
            throw CloudSyncFailure.server("BLUEPRINT_LINK_UNAVAILABLE")
        })
        #expect(model.hasPendingInstallation && model.entry == nil)
        #expect(model.errorMessage == BlueprintCopy.sharedLinkUnavailable)
    }

    @Test("Missing identity or malformed links cannot access receipts, drafts or the network")
    func invalidIdentity() async {
        for (ownerID, incoming) in [(nil as String?, token), ("", token), ("A", "invalid")] {
            let model = BlueprintSharedPreviewModel()
            var calls = 0
            await model.load(ownerID: ownerID, token: incoming, pendingInstallation: {
                calls += 1
                return false
            }, savedDraft: {
                calls += 1
                return nil
            }, fetch: {
                calls += 1
                throw CloudSyncFailure.invalidResponse
            })
            #expect(calls == 0 && model.entry == nil && !model.isLoading)
        }
    }

    @Test("Closing setup returns to the shared preview; successful installation finishes the shared handoff")
    func setupExit() {
        #expect(!BlueprintSetupExitPolicy.dismissesSharedLink(hasSharedToken: true, returnsToPreview: true, didComplete: false))
        #expect(BlueprintSetupExitPolicy.dismissesSharedLink(hasSharedToken: true, returnsToPreview: true, didComplete: true))
        #expect(BlueprintSetupExitPolicy.dismissesSharedLink(hasSharedToken: true, returnsToPreview: false, didComplete: false))
        #expect(!BlueprintSetupExitPolicy.dismissesSharedLink(hasSharedToken: false, returnsToPreview: true, didComplete: true))
    }

    private func fixture() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: SharedPreviewFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries[0]
    }

    private func savedDraft() throws -> BlueprintSetupDraft {
        .init(
            ownerUserID: "A", entry: try fixture(), requestID: UUID(), eventName: "Edited name",
            startsAt: Date(timeIntervalSince1970: 1_811_923_200), timeZoneIdentifier: "America/Detroit",
            selectedChildren: ["ceremony"], selectedIdeas: ["flowers"],
            confirmedDates: ["ceremony": Date(timeIntervalSince1970: 1_811_923_200)],
            shareToken: token
        )
    }
}

private final class SharedPreviewFixtureBundle: NSObject {}
