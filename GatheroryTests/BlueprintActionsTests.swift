import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintActionsTests {
    @Test("Preference retries reuse the request ID and commit only the server acknowledgement")
    func retryAndCommit() async throws {
        let entry = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        transport.updateFailuresRemaining = 1
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        #expect(!(await store.set(.like, enabled: true, for: entry)))
        #expect(store.states[entry.catalogKey] == nil)
        #expect(await store.set(.like, enabled: true, for: entry))
        #expect(transport.mutations.count == 2)
        #expect(transport.mutations[0].requestId == transport.mutations[1].requestId)
        #expect(store.states[entry.catalogKey]?.liked == true)
    }

    @Test("Account reset purges state and ignores a late action response")
    func accountResetDropsLateResponse() async throws {
        let entry = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        transport.updateDelay = .milliseconds(60)
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        let action = Task { await store.set(.bookmark, enabled: true, for: entry) }
        try await Task.sleep(for: .milliseconds(5))
        store.resetForAccountChange()
        _ = await action.value
        #expect(store.states.isEmpty)
        #expect(store.savedItems.isEmpty)
        #expect(!store.measurementEnabled)
    }

    @Test("Serialized preference commands reach the server in order")
    func serializesCommands() async throws {
        let entry = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        transport.updateDelay = .milliseconds(15)
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        let like = Task { await store.set(.like, enabled: true, for: entry) }
        while transport.mutations.isEmpty { await Task.yield() }
        let bookmark = Task { await store.set(.bookmark, enabled: true, for: entry) }
        #expect(await like.value)
        #expect(await bookmark.value)
        #expect(transport.mutations.map(\.kind) == [.like, .bookmark])
    }

    @Test("Passive impressions require half visibility for one second in an active non-preview scene")
    func visibilityThreshold() {
        #expect(!BlueprintImpressionPolicy.qualifies(visibleFraction: 0.49, visibleDuration: 3,
            sceneIsActive: true, previewIsPresented: false))
        #expect(!BlueprintImpressionPolicy.qualifies(visibleFraction: 0.5, visibleDuration: 0.99,
            sceneIsActive: true, previewIsPresented: false))
        #expect(!BlueprintImpressionPolicy.qualifies(visibleFraction: 1, visibleDuration: 2,
            sceneIsActive: false, previewIsPresented: false))
        #expect(!BlueprintImpressionPolicy.qualifies(visibleFraction: 1, visibleDuration: 2,
            sceneIsActive: true, previewIsPresented: true))
        #expect(BlueprintImpressionPolicy.qualifies(visibleFraction: 0.5, visibleDuration: 1,
            sceneIsActive: true, previewIsPresented: false))
    }

    @Test("Measurement stays off until the default is acknowledged")
    func measurementWaitsForDefaultAcknowledgement() async throws {
        let base = try catalogEntry()
        let context = BlueprintDiscoveryContext(exposureId: "exposure-1", expiresAt: Date().addingTimeInterval(60))
        let entry = BlueprintCatalogEntry(catalogKey: base.catalogKey, revision: base.revision,
            contentHash: base.contentHash, definition: base.definition, viewerState: .init(), discoveryContext: context)
        let transport = FakeBlueprintActionsTransport()
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        await store.record(.impression, for: entry)
        await store.record(.open, for: entry)
        #expect(transport.signals.isEmpty)
        #expect(!store.measurementEnabled)
        #expect(transport.settingMutationCount == 0)
    }

    @Test("Expired exposure IDs are dropped and opted-in signals deduplicate per exposure and kind")
    func measurementExpiryAndDeduplication() async throws {
        let base = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        let expired = BlueprintCatalogEntry(catalogKey: base.catalogKey, revision: base.revision,
            contentHash: base.contentHash, definition: base.definition, viewerState: .init(),
            discoveryContext: .init(exposureId: "expired", expiresAt: Date().addingTimeInterval(-1)))
        #expect(await store.setMeasurementEnabled(true))
        await store.record(.impression, for: expired)
        #expect(transport.signals.isEmpty)

        let live = BlueprintCatalogEntry(catalogKey: base.catalogKey, revision: base.revision,
            contentHash: base.contentHash, definition: base.definition, viewerState: .init(),
            discoveryContext: .init(exposureId: "live", expiresAt: Date().addingTimeInterval(60)))
        await store.record(.impression, for: live)
        await store.record(.impression, for: live)
        await store.record(.open, for: live)
        #expect(transport.signals.map(\.kind) == [.impression, .open])
    }

    @Test("Loading a disabled server setting enables the default only after acknowledgement")
    func measurementDefaultIsAcknowledged() async {
        let transport = FakeBlueprintActionsTransport()
        transport.settingWriteDelay = .milliseconds(50)
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        let load = Task { await store.loadMeasurementSetting() }
        while transport.settingRequestIDs.isEmpty { await Task.yield() }
        #expect(!store.measurementEnabled)
        await load.value
        #expect(store.measurementEnabled)
        #expect(transport.settingMutationCount == 1)
        #expect(transport.settingRequestIDs.count == 1)
    }

    @Test("Failed default enable stays off and retries the same acknowledged-setting request")
    func failedMeasurementDefaultCanRetry() async {
        let transport = FakeBlueprintActionsTransport()
        transport.settingFailuresRemaining = 1
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        await store.loadMeasurementSetting()
        #expect(!store.measurementEnabled)
        let requestID = transport.settingRequestIDs.last
        #expect(requestID != nil)
        await store.retryMeasurementSetting()
        #expect(store.measurementEnabled)
        #expect(transport.settingRequestIDs.count == 2)
        #expect(transport.settingRequestIDs[0] == requestID)
    }

    @Test("A setting read from a prior account cannot enable measurement after reset")
    func staleMeasurementReadDoesNotCrossAccountReset() async {
        let transport = FakeBlueprintActionsTransport()
        transport.settingReadDelay = .milliseconds(50)
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        let load = Task { await store.loadMeasurementSetting() }
        while transport.settingReadCount == 0 { await Task.yield() }
        store.resetForAccountChange()
        await load.value
        #expect(!store.measurementEnabled)
        #expect(transport.settingMutationCount == 0)
    }

    @Test("An explicit disabled setting read is not overwritten by a stale read")
    func explicitMeasurementResetWinsReadRace() async {
        let transport = FakeBlueprintActionsTransport()
        transport.settingReadDelay = .milliseconds(50)
        transport.setting = .init(enabled: true)
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        let load = Task { await store.loadMeasurementSetting() }
        while transport.settingReadCount == 0 { await Task.yield() }
        #expect(await store.setMeasurementEnabled(false))
        await load.value
        #expect(!store.measurementEnabled)
        #expect(transport.settingMutationCount == 1)
    }

    @Test("Consent retry reuses the failed setting request instead of retrying an older card action")
    func consentRetryIsIndependentOfCardFailures() async throws {
        let entry = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        transport.updateFailuresRemaining = 1
        #expect(!(await store.set(.like, enabled: true, for: entry)))
        #expect(await store.setMeasurementEnabled(true))
        transport.settingFailuresRemaining = 1
        #expect(!(await store.setMeasurementEnabled(false)))
        let failedRequest = transport.settingRequestIDs.last
        await store.retryMeasurementSetting()
        #expect(!store.measurementEnabled)
        #expect(transport.mutations.count == 1)
        #expect(transport.settingRequestIDs.last == failedRequest)
        #expect(transport.settingMutationCount == 3)
    }

    @Test("Preference refresh clears server-removed keys when no newer action exists")
    func refreshClearsDeletedPreferences() async throws {
        let entry = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        #expect(await store.set(.like, enabled: true, for: entry))
        await store.loadPreferences()
        #expect(store.states[entry.catalogKey] == nil)
        #expect(store.savedItems.isEmpty)
    }

    @Test("Failed preference refresh keeps saved references and exposes a retry state")
    func failedPreferenceRefreshPreservesReferences() async throws {
        let entry = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        #expect(await store.set(.bookmark, enabled: true, for: entry))
        let savedBeforeRefresh = store.savedItems
        transport.preferenceFailuresRemaining = 1
        await store.loadPreferences()
        #expect(store.preferencesLoadFailed)
        #expect(!store.isLoading)
        #expect(store.savedItems == savedBeforeRefresh)
        #expect(store.states[entry.catalogKey]?.bookmarked == true)
    }

    @Test("Refresh preserves acknowledged actions that complete while the server snapshot is in flight")
    func refreshPreservesConcurrentMutation() async throws {
        let entry = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        transport.preferencesDelay = .milliseconds(60)
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        let refresh = Task { await store.loadPreferences() }
        while transport.preferencesCalls == 0 { await Task.yield() }
        #expect(await store.set(.bookmark, enabled: true, for: entry))
        await refresh.value
        #expect(store.states[entry.catalogKey]?.bookmarked == true)
        #expect(store.savedItems.first(where: { $0.catalogKey == entry.catalogKey })?.bookmarked == true)
    }

    @Test("Explore and account settings observe the same acknowledged preference and consent state")
    func sharedAccountStoreState() async throws {
        let entry = try catalogEntry()
        let transport = FakeBlueprintActionsTransport()
        let exploreStore = BlueprintActionStore(ownerID: "account-a", transport: transport)
        let accountStore = exploreStore
        #expect(await accountStore.set(.notInterested, enabled: true, for: entry))
        #expect(exploreStore.states[entry.catalogKey]?.notInterested == true)
        #expect(await accountStore.setMeasurementEnabled(true))
        let measuredEntry = BlueprintCatalogEntry(catalogKey: entry.catalogKey, revision: entry.revision,
            contentHash: entry.contentHash, definition: entry.definition, viewerState: .init(),
            discoveryContext: .init(exposureId: "account-shared-exposure", expiresAt: Date().addingTimeInterval(60)))
        await exploreStore.record(.open, for: measuredEntry)
        #expect(accountStore.measurementEnabled)
        #expect(transport.signals.map(\.exposureId) == ["account-shared-exposure"])
    }

    @Test("Liked-only references stay in Liked when Saves are unavailable")
    func likedOnlyAvailability() throws {
        let item = try savedPreference(liked: true, bookmarked: false,
            likeRevision: 4, likeContentHash: String(repeating: "a", count: 64),
            bookmarkAvailability: "unavailable", likeAvailability: "available")
        #expect(item.isLikeAvailable)
        #expect(!item.isAvailable)
        #expect(item.binding(for: .like).revision == 4)
    }

    @Test("Like and Save removals use separate stale bindings and preserve the other action")
    func independentPreferenceBindings() async throws {
        let item = try savedPreference(liked: true, bookmarked: true,
            revision: 7, contentHash: String(repeating: "b", count: 64),
            likeRevision: 4, likeContentHash: String(repeating: "a", count: 64),
            bookmarkRevision: 7, bookmarkContentHash: String(repeating: "b", count: 64))
        let transport = FakeBlueprintActionsTransport()
        transport.states[item.catalogKey] = .init(liked: true, bookmarked: true)
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)

        #expect(await store.set(.like, enabled: false, for: item))
        #expect(transport.mutations.last?.revision == 4)
        #expect(transport.mutations.last?.contentHash == String(repeating: "a", count: 64))
        #expect(store.states[item.catalogKey]?.liked == false)
        #expect(store.states[item.catalogKey]?.bookmarked == true)

        let afterLikeRemoval = try #require(store.savedItems.first)
        #expect(await store.set(.bookmark, enabled: false, for: afterLikeRemoval))
        #expect(transport.mutations.last?.revision == 7)
        #expect(transport.mutations.last?.contentHash == String(repeating: "b", count: 64))
        #expect(store.states[item.catalogKey] == nil)
    }

    @Test("Collection opening resolves only the current public entry and drops discovery context")
    func currentPublicEntryResolution() throws {
        let item = try savedPreference(liked: true, bookmarked: false,
            likeRevision: 2, likeContentHash: String(repeating: "a", count: 64),
            bookmarkAvailability: "unavailable", likeAvailability: "available")
        let base = try catalogEntry()
        let current = BlueprintCatalogEntry(catalogKey: item.catalogKey, revision: 8,
            contentHash: String(repeating: "c", count: 64), definition: base.definition,
            viewerState: .init(liked: false, bookmarked: true),
            discoveryContext: .init(exposureId: "explore-exposure", expiresAt: Date().addingTimeInterval(60)))
        let store = BlueprintActionStore(ownerID: "account-a", transport: FakeBlueprintActionsTransport())

        let resolved = try #require(store.publicEntry(for: item, in: [current]))
        #expect(resolved.revision == 8)
        #expect(resolved.viewerState == .init(liked: false, bookmarked: true))
        #expect(resolved.discoveryContext == nil)
        #expect(store.publicEntry(for: item, in: []) == nil)

        let noViewerState = BlueprintCatalogEntry(catalogKey: item.catalogKey, revision: 8,
            contentHash: String(repeating: "c", count: 64), definition: base.definition)
        let fallback = try #require(store.publicEntry(for: item, in: [noViewerState]))
        #expect(fallback.viewerState == .init(liked: true, bookmarked: false, notInterested: false))
    }

    @Test("Acknowledging another action preserves a legacy fallback binding")
    func preservesLegacyFallbackBinding() async throws {
        let hash = String(repeating: "a", count: 64)
        let item = try savedPreference(liked: true, bookmarked: false,
            revision: 4, contentHash: hash, bookmarkAvailability: "unavailable")
        let base = try catalogEntry()
        let entry = BlueprintCatalogEntry(catalogKey: item.catalogKey, revision: 9,
            contentHash: String(repeating: "c", count: 64), definition: base.definition,
            viewerState: .init(liked: true))
        let transport = FakeBlueprintActionsTransport()
        transport.preferenceItems = [item]
        transport.states[item.catalogKey] = .init(liked: true)
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)
        await store.loadPreferences()

        #expect(await store.set(.notInterested, enabled: true, for: entry))
        let updated = try #require(store.savedItems.first)
        #expect(updated.binding(for: .like).revision == 4)
        #expect(updated.binding(for: .like).contentHash == hash)
        #expect(updated.isLikeAvailable)
        #expect(updated.bookmarkAvailability == "available")
        #expect(updated.notInterestedAvailability == "available")

        #expect(await store.set(.like, enabled: false, for: updated))
        #expect(transport.mutations.last?.revision == 4)
        #expect(transport.mutations.last?.contentHash == hash)
    }

    @Test("The latest concurrent preference refresh wins when an older response arrives last")
    func latestPreferenceRefreshWins() async throws {
        let olderItem = try savedPreference(liked: true, bookmarked: false, catalogKey: "older_key")
        let newerItem = try savedPreference(liked: false, bookmarked: true, catalogKey: "newer_key")
        let transport = FakeBlueprintActionsTransport()
        transport.preferenceResponsesByCall = [1: [olderItem], 2: [newerItem]]
        transport.preferenceDelaysByCall = [1: .milliseconds(80), 2: .milliseconds(5)]
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)

        let olderLoad = Task { await store.loadPreferences() }
        while transport.preferencesCalls < 1 { await Task.yield() }
        let newerLoad = Task { await store.loadPreferences() }
        await newerLoad.value
        #expect(store.savedItems.map(\.catalogKey) == ["newer_key"])
        await olderLoad.value
        #expect(store.savedItems.map(\.catalogKey) == ["newer_key"])
        #expect(store.states["older_key"] == nil)
        #expect(store.states["newer_key"]?.bookmarked == true)
        #expect(!store.isLoading)
    }

    @Test("A late failure from an older preference refresh cannot replace a newer success")
    func olderPreferenceFailureCannotClobberNewerSuccess() async throws {
        let olderItem = try savedPreference(liked: true, bookmarked: false, catalogKey: "older_key")
        let newerItem = try savedPreference(liked: false, bookmarked: true, catalogKey: "newer_key")
        let transport = FakeBlueprintActionsTransport()
        transport.preferenceResponsesByCall[2] = [newerItem]
        transport.preferenceDelaysByCall = [1: .milliseconds(80), 2: .milliseconds(5)]
        transport.preferenceFailuresByCall = [1]
        let store = BlueprintActionStore(ownerID: "account-a", transport: transport)

        let olderLoad = Task { await store.loadPreferences() }
        while transport.preferencesCalls < 1 { await Task.yield() }
        let newerLoad = Task { await store.loadPreferences() }
        await newerLoad.value
        await olderLoad.value

        #expect(store.savedItems.map(\.catalogKey) == ["newer_key"])
        #expect(!store.preferencesLoadFailed)
        #expect(!store.isLoading)
    }

    @Test("Copy source keeps optional exposure attribution backwards compatible")
    func copySourceExposureDecoding() throws {
        let source = BlueprintCopySource(catalogKey: "public-key", revision: 4, shareToken: nil,
                                         discoveryExposureId: "exposure-123")
        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(BlueprintCopySource.self, from: encoded)
        #expect(decoded.discoveryExposureId == "exposure-123")
        let legacy = Data("{\"catalogKey\":\"public-key\",\"revision\":4,\"shareToken\":null}".utf8)
        #expect(try JSONDecoder().decode(BlueprintCopySource.self, from: legacy).discoveryExposureId == nil)
    }

    private func catalogEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: ActionsFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        var entry = try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries[0]
        entry.viewerState = .init()
        return entry
    }

    private func savedPreference(liked: Bool, bookmarked: Bool,
        catalogKey: String = "public_key",
        revision: Int = 7, contentHash: String = String(repeating: "b", count: 64),
        likeRevision: Int? = nil, likeContentHash: String? = nil,
        bookmarkRevision: Int? = nil, bookmarkContentHash: String? = nil,
        bookmarkAvailability: String = "available", likeAvailability: String? = nil
    ) throws -> BlueprintSavedPreference {
        var object: [String: Any] = [
            "catalogKey": catalogKey, "revision": revision, "contentHash": contentHash,
            "liked": liked, "bookmarked": bookmarked, "notInterested": false,
            "bookmarkAvailability": bookmarkAvailability,
            "entry": ["name": "Public plan"],
        ]
        if let likeRevision { object["likeRevision"] = likeRevision }
        if let likeContentHash { object["likeContentHash"] = likeContentHash }
        if let bookmarkRevision { object["bookmarkRevision"] = bookmarkRevision }
        if let bookmarkContentHash { object["bookmarkContentHash"] = bookmarkContentHash }
        if let likeAvailability { object["likeAvailability"] = likeAvailability }
        return try JSONDecoder().decode(BlueprintSavedPreference.self,
            from: JSONSerialization.data(withJSONObject: object))
    }
}

@MainActor
private final class FakeBlueprintActionsTransport: BlueprintActionsTransport {
    var mutations: [BlueprintPreferenceMutation] = []
    var states: [String: BlueprintViewerState] = [:]
    var signals: [BlueprintMeasurementSignal] = []
    var updateFailuresRemaining = 0
    var settingFailuresRemaining = 0
    var settingRequestIDs: [UUID] = []
    var updateDelay: Duration = .zero
    var preferencesDelay: Duration = .zero
    var preferencesCalls = 0
    var preferenceItems: [BlueprintSavedPreference] = []
    var preferenceFailuresRemaining = 0
    var preferenceResponsesByCall: [Int: [BlueprintSavedPreference]] = [:]
    var preferenceDelaysByCall: [Int: Duration] = [:]
    var preferenceFailuresByCall = Set<Int>()
    var settingMutationCount = 0
    var settingReadCount = 0
    var settingReadDelay: Duration = .zero
    var settingWriteDelay: Duration = .zero
    var setting = BlueprintMeasurementSettings(enabled: false)

    func update(_ mutation: BlueprintPreferenceMutation) async throws -> BlueprintPreferenceAcknowledgement {
        mutations.append(mutation)
        if updateDelay > .zero { try await Task.sleep(for: updateDelay) }
        if updateFailuresRemaining > 0 {
            updateFailuresRemaining -= 1
            throw URLError(.networkConnectionLost)
        }
        let prior = states[mutation.catalogKey] ?? BlueprintViewerState()
        let state = switch mutation.kind {
        case .like: BlueprintViewerState(liked: mutation.enabled, bookmarked: prior.bookmarked, notInterested: prior.notInterested)
        case .bookmark: BlueprintViewerState(liked: prior.liked, bookmarked: mutation.enabled, notInterested: prior.notInterested)
        case .notInterested: BlueprintViewerState(liked: prior.liked, bookmarked: prior.bookmarked, notInterested: mutation.enabled)
        }
        states[mutation.catalogKey] = state
        return .init(requestId: mutation.requestId, catalogKey: mutation.catalogKey, revision: mutation.revision,
                     contentHash: mutation.contentHash, liked: state.liked, bookmarked: state.bookmarked,
                     notInterested: state.notInterested)
    }

    func preferences(cursor: String?) async throws -> BlueprintPreferencesPage {
        preferencesCalls += 1
        let call = preferencesCalls
        if let delay = preferenceDelaysByCall[call], delay > .zero { try await Task.sleep(for: delay) }
        if preferencesDelay > .zero { try await Task.sleep(for: preferencesDelay) }
        if preferenceFailuresByCall.contains(call) { throw URLError(.networkConnectionLost) }
        if preferenceFailuresRemaining > 0 {
            preferenceFailuresRemaining -= 1
            throw URLError(.networkConnectionLost)
        }
        return .init(items: preferenceResponsesByCall[call] ?? preferenceItems)
    }
    func measurementSettings() async throws -> BlueprintMeasurementSettings {
        settingReadCount += 1
        if settingReadDelay > .zero { try await Task.sleep(for: settingReadDelay) }
        return setting
    }
    func setMeasurementSettings(requestID: UUID, enabled: Bool) async throws -> BlueprintMeasurementSettings {
        settingRequestIDs.append(requestID)
        if settingWriteDelay > .zero { try await Task.sleep(for: settingWriteDelay) }
        if settingFailuresRemaining > 0 {
            settingMutationCount += 1
            settingFailuresRemaining -= 1
            throw URLError(.networkConnectionLost)
        }
        settingMutationCount += 1
        setting = .init(enabled: enabled)
        return setting
    }
    func record(_ signal: BlueprintMeasurementSignal) async throws { signals.append(signal) }
}

private final class ActionsFixtureBundle: NSObject {}
