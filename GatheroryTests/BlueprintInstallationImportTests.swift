import Foundation
import SwiftData
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct BlueprintInstallationImportTests {
    @Test("Copied draft import cleans the original local identity and records the independent private pin")
    func copiedDraftUsesCanonicalImportAndExactCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = BlueprintSetupDraftStore(directoryURL: directory.appending(path: "drafts"))
        let intents = BlueprintInstallationIntentStore(directoryURL: directory.appending(path: "intents"))
        let history = BlueprintLibraryCache(directoryURL: directory.appending(path: "history"))
        let archiveData = try weddingFixtureData()
        let archive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: archiveData)
        let ownerID = try #require(archive.members.first?.userID)
        let fixtureURL = try #require(Bundle(for: BlueprintInstallURLProtocol.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let source = try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: fixtureURL)).entries.first)
        let copied = BlueprintCatalogEntry(catalogKey: "private_independent_copy", revision: 1,
            contentHash: String(repeating: "b", count: 64), definition: source.definition)
        let originalInput = weddingInstallInput()
        let input = BlueprintInstallInput(requestID: originalInput.requestID, catalogKey: copied.catalogKey,
            revision: copied.revision, contentHash: copied.contentHash, mainEvent: originalInput.mainEvent,
            selectedChildren: originalInput.selectedChildren, selectedIdeaKeys: originalInput.selectedIdeaKeys,
            capabilities: originalInput.capabilities)
        let entryToken = String(repeating: "ab", count: 32)
        try drafts.save(BlueprintSetupDraft(ownerUserID: ownerID, entry: source, requestID: input.requestID,
            eventName: input.mainEvent.name, startsAt: input.mainEvent.startsAt, timeZoneIdentifier: input.mainEvent.timeZone,
            selectedChildren: Set(input.selectedChildren.map(\.key)), selectedIdeas: Set(input.selectedIdeaKeys),
            confirmedDates: [:], shareToken: entryToken, copyRequestID: UUID(), copyEntry: copied))
        BlueprintInstallURLProtocol.configure(archiveBytes: archiveData, scopeID: archive.mainEventID, loseInstallResponse: false,
            expectedContentHashes: [input.requestID.uuidString.lowercased(): copied.contentHash])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlueprintInstallURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(baseURL: URL(string: "https://blueprint-install.invalid")!,
            urlSession: session, tokenStore: BlueprintInstallTokenStore())
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
        let coordinator = BlueprintInstallationCoordinator(baseURL: URL(string: "https://blueprint-install.invalid")!,
            persistence: persistence, library: library, intents: intents, setupDrafts: drafts,
            transport: transport, libraryCache: history)
        let imported = try await coordinator.install(input, ownerUserID: ownerID)
        #expect(imported.mainEventID == archive.mainEventID)
        #expect(try drafts.all(ownerUserID: ownerID).isEmpty)
        #expect(try intents.pending(ownerUserID: ownerID).isEmpty)
        let receipt = try #require(try history.load(ownerID: ownerID).first)
        let snapshot = try #require(try receipt.previewSource(ownerID: ownerID))
        #expect(receipt.catalogKey == copied.catalogKey)
        #expect(snapshot.entry.catalogKey == copied.catalogKey)
        #expect(snapshot.copyEntry == nil && snapshot.shareToken == nil)
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        let body = try #require(JSONSerialization.jsonObject(with: BlueprintInstallURLProtocol.lastInstallBody) as? [String: Any])
        #expect(body["shareToken"] == nil)
        #expect(body["catalogKey"] as? String == copied.catalogKey)
    }

    @Test("Plans recover exact requests without outbox edits even when history caching fails", arguments: [false, true], [false, true])
    func installUsesFixtureBootstrapAndRecoversReceipt(customized: Bool, historyWritesFail: Bool) async throws {
        let storeURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        let intentDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let setupDrafts = BlueprintSetupDraftStore(directoryURL: intentDirectory.appending(path: "setup-drafts"))
        let historyURL = intentDirectory.appending(path: "used-history")
        let historyCache = BlueprintLibraryCache(directoryURL: historyURL)
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
            try? FileManager.default.removeItem(at: intentDirectory)
        }

        var fixtureArchive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: weddingFixtureData())
        let venueID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let visitID = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        if customized {
            let ideaIndex = try #require(fixtureArchive.ideas.firstIndex { $0.id == venueID })
            let childIndex = try #require(fixtureArchive.timeline.firstIndex { $0.id == visitID })
            fixtureArchive.ideas[ideaIndex].title = "Garden venue"
            fixtureArchive.ideas[ideaIndex].note = "Our notes"
            fixtureArchive.timeline[childIndex].title = "Private venue tour"
        }
        let fixtureData = try WorkspaceArchiveCodec().encode(fixtureArchive)
        if historyWritesFail {
            try FileManager.default.createDirectory(at: intentDirectory, withIntermediateDirectories: true)
            try Data("Unavailable cache directory".utf8).write(to: historyURL)
        }
        let ownerID = try #require(fixtureArchive.members.first?.userID)
        let account = UserAccount(
            id: ownerID, email: "riley@example.test", displayName: "Riley Example",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
        #expect(fixtureArchive.currencyCode == "USD")
        #expect(fixtureArchive.guides?.count == 2)
        #expect(fixtureArchive.experienceConfiguration?.experienceType == "wedding")
        BlueprintInstallURLProtocol.configure(
            archiveBytes: fixtureData,
            scopeID: fixtureArchive.mainEventID,
            revokeSharedTokenAfterLostResponse: true
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlueprintInstallURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(
            baseURL: URL(string: "https://blueprint-install.invalid")!,
            urlSession: session,
            tokenStore: BlueprintInstallTokenStore()
        )

        let importedScopeID: UUID
        do {
            let persistence = try WorkspacePersistenceController(storeURL: storeURL)
            let library = persistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
            library.configureViewer(account)
            let coordinator = BlueprintInstallationCoordinator(
                baseURL: URL(string: "https://blueprint-install.invalid")!,
                persistence: persistence,
                library: library,
                intents: BlueprintInstallationIntentStore(directoryURL: intentDirectory),
                setupDrafts: setupDrafts,
                transport: transport,
                libraryCache: historyCache
            )
            let shareToken = String(repeating: "f6", count: 32)
            var input = weddingInstallInput(shareToken: shareToken)
            if customized {
                input.customizations = BlueprintCustomization(
                    children: [.init(key: "venue_visit", title: "Private venue tour", purpose: "planning_scouting", category: "venue", scheduleProposal: nil)],
                    ideas: [.init(key: "venue", title: "Garden venue", category: "venue", notes: "Our notes", target: .main, configuration: ["version": .integer(1)])]
                )
            }
            let catalogURL = try #require(Bundle(for: BlueprintInstallURLProtocol.self)
                .url(forResource: "wedding-catalog.v1", withExtension: "json"))
            let entry = try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: catalogURL)).entries.first)
            try setupDrafts.save(BlueprintSetupDraft(
                ownerUserID: ownerID, entry: entry, requestID: input.requestID,
                eventName: input.mainEvent.name, startsAt: input.mainEvent.startsAt,
                timeZoneIdentifier: input.mainEvent.timeZone,
                selectedChildren: Set(input.selectedChildren.map(\.key)),
                selectedIdeas: Set(input.selectedIdeaKeys),
                confirmedDates: Dictionary(uniqueKeysWithValues: input.selectedChildren.map { ($0.key, $0.startsAt) }),
                shareToken: shareToken,
                customizations: input.customizations
            ))

            do {
                _ = try await coordinator.install(input, ownerUserID: ownerID)
                Issue.record("The fixture server should lose the first install response")
            } catch let error as URLError {
                #expect(error.code == .networkConnectionLost)
            }

            let persistedIntents = try BlueprintInstallationIntentStore(directoryURL: intentDirectory)
                .pending(ownerUserID: ownerID)
            let pendingIntent = try #require(persistedIntents.first)
            let bodyText = try #require(String(data: pendingIntent.requestBody, encoding: .utf8))
            #expect(bodyText.hasPrefix("{\"capabilities\""))
            #expect((try JSONSerialization.jsonObject(with: pendingIntent.requestBody) as? [String: Any])?["shareToken"] as? String == shareToken)
            #expect(BlueprintInstallURLProtocol.lastInstallBody == pendingIntent.requestBody)
            let body = try #require(JSONSerialization.jsonObject(with: pendingIntent.requestBody) as? [String: Any])
            #expect((body["customizations"] != nil) == customized)
            if customized {
                let overlay = try #require(body["customizations"] as? [String: Any])
                #expect((overlay["ideas"] as? [[String: Any]])?.first?["title"] as? String == "Garden venue")
                #expect((overlay["children"] as? [[String: Any]])?.first?["title"] as? String == "Private venue tour")
            }
            #expect(persistedIntents.count == 1)
            if !historyWritesFail { #expect(try historyCache.load(ownerID: ownerID).isEmpty) }
            #expect(try setupDrafts.load(ownerUserID: ownerID, catalogKey: "wedding", shareToken: shareToken)?.requestID == input.requestID)

            // A new coordinator/store instance represents relaunch. The receipt
            // lets it recover without a second POST, then normal bootstrap owns
            // the only local import path.
            let relaunched = BlueprintInstallationCoordinator(
                baseURL: URL(string: "https://blueprint-install.invalid")!,
                persistence: persistence,
                library: library,
                intents: BlueprintInstallationIntentStore(directoryURL: intentDirectory),
                setupDrafts: setupDrafts,
                transport: transport,
                libraryCache: historyCache
            )
            let imported = try await relaunched.resume(pendingIntent)
            importedScopeID = imported.mainEventID

            #expect(importedScopeID == fixtureArchive.mainEventID)
            #expect(imported.currencyCode == "USD")
            #expect(imported.guides == fixtureArchive.guides)
            #expect(imported.experienceConfiguration == fixtureArchive.experienceConfiguration)
            #expect(imported.ideas.count == 3)
            #expect(imported.timeline.count == 2)
            #expect(imported.showsPlanningInterface)
            #expect(imported.canManageMainEvent)
            #expect(Set(imported.timeline.map(\.id)) == Set([
                UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
                UUID(uuidString: "10000000-0000-4000-8000-000000000003")!
            ]))
            #expect(imported.timeline.allSatisfy { $0.status == .approved })
            #expect(Set(imported.ideas.map(\.id)) == Set([
                UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
                UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
                UUID(uuidString: "20000000-0000-4000-8000-000000000003")!
            ]))
            #expect(imported.ideas.allSatisfy { $0.status == .new })
            if customized {
                #expect(imported.ideas.first { $0.id == venueID }?.title == "Garden venue")
                #expect(imported.ideas.first { $0.id == venueID }?.note == "Our notes")
                #expect(imported.timeline.first { $0.id == visitID }?.title == "Private venue tour")
            }
            #expect(library.selectedWorkspaceID == fixtureArchive.mainEventID)
            #expect(try BlueprintInstallationIntentStore(directoryURL: intentDirectory)
                .pending(ownerUserID: ownerID).isEmpty)
            #expect(try setupDrafts.load(ownerUserID: ownerID, catalogKey: "wedding", shareToken: shareToken) == nil)
            #expect(try setupDrafts.all(ownerUserID: ownerID).isEmpty)
            if !historyWritesFail {
                let history = try historyCache.load(ownerID: ownerID)
                #expect(history.count == 1)
                #expect(history.first?.scopeID == importedScopeID)
                #expect(history.first?.catalogKey == entry.catalogKey)
                #expect(history.first?.revision == entry.revision)
                #expect(history.first?.templateName == entry.definition.blueprint.name)
                #expect(history.first?.eventName == input.mainEvent.name)
            }
            #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).isEmpty)
            #expect(BlueprintInstallURLProtocol.installRequestCount == 1)
            #expect(BlueprintInstallURLProtocol.lastInstallBody == pendingIntent.requestBody)

            // Merely opening or saving the imported plan must not synthesize
            // decisions or an outbox edit before the user changes anything.
            try persistence.saveChanges(in: library)
            #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).isEmpty)

            imported.title = "Local edit after Wedding install"
            try persistence.saveChanges(in: library)
            #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).count == 1)
        }

        // Reopen the actual on-disk SwiftData store. Snapshot metadata and the
        // local edit survive, and its normal workspace outbox remains queued.
        let restartedPersistence = try WorkspacePersistenceController(storeURL: storeURL)
        let restartedLibrary = restartedPersistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
        let restored = try #require(restartedLibrary.workspaces.first { $0.mainEventID == importedScopeID })
        #expect(restored.title == "Local edit after Wedding install")
        #expect(restored.currencyCode == "USD")
        #expect(restored.guides.count == 2)
        #expect(restored.experienceConfiguration?.categoryOrder == ["venue", "attire", "food", "flowers", "photography"])
        #expect(try ModelContext(restartedPersistence.container).fetch(FetchDescriptor<PendingMutation>()).count == 1)
    }

    @Test("A failed receipt retries the same request and can import successfully")
    func failedReceiptReacquiresSameRequest() async throws {
        let fixtureData = try weddingFixtureData()
        let archive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: fixtureData)
        let ownerID = try #require(archive.members.first?.userID)
        let account = UserAccount(
            id: ownerID, email: "riley@example.test", displayName: "Riley Example",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
        BlueprintInstallURLProtocol.configure(
            archiveBytes: fixtureData,
            scopeID: archive.mainEventID,
            initialStatus: "failed",
            loseInstallResponse: false
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlueprintInstallURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(
            baseURL: URL(string: "https://blueprint-install.invalid")!,
            urlSession: session,
            tokenStore: BlueprintInstallTokenStore()
        )
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
        library.configureViewer(account)
        let intentDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: intentDirectory) }
        let coordinator = BlueprintInstallationCoordinator(
            baseURL: URL(string: "https://blueprint-install.invalid")!,
            persistence: persistence,
            library: library,
            intents: BlueprintInstallationIntentStore(directoryURL: intentDirectory),
            transport: transport
        )
        let input = weddingInstallInput()

        let imported = try await coordinator.install(input, ownerUserID: ownerID)

        #expect(imported.mainEventID == archive.mainEventID)
        #expect(imported.guides == archive.guides)
        #expect(BlueprintInstallURLProtocol.installRequestCount == 1)
        #expect(BlueprintInstallURLProtocol.lastInstallRequestID == input.requestID.uuidString.lowercased())
        let expectedEncoder = JSONEncoder()
        expectedEncoder.outputFormatting = [.sortedKeys]
        expectedEncoder.dateEncodingStrategy = .iso8601
        #expect(BlueprintInstallURLProtocol.lastInstallBody == (try expectedEncoder.encode(input)))
        #expect(try BlueprintInstallationIntentStore(directoryURL: intentDirectory)
            .pending(ownerUserID: ownerID).isEmpty)
    }

    @Test("Bootstrap saves edits made to another workspace while the response is in flight")
    func bootstrapFlushesConcurrentWorkspaceEdit() async throws {
        let fixtureData = try weddingFixtureData()
        let archive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: fixtureData)
        let ownerID = try #require(archive.members.first?.userID)
        let account = UserAccount(
            id: ownerID, email: "riley@example.test", displayName: "Riley Example",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
        library.configureViewer(account)
        let existing = PlanningWorkspace.newWorkspace(
            title: "Existing workspace",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            eventLocation: nil,
            imageData: nil,
            owner: account
        )
        library.add(existing)
        let existingArchive = try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: existing))
        try persistence.applyBootstrap([
            RemoteWorkspaceSnapshot(
                scopeID: existing.mainEventID,
                payloadSchemaVersion: 1,
                payload: existingArchive,
                serverVersion: 1,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ], to: library)
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        persistence.startObserving(library)
        let baselineImportedWorkspace = try #require(
            library.workspaces.first { $0.mainEventID == existing.mainEventID }
        )
        BlueprintInstallURLProtocol.configure(
            archiveBytes: fixtureData,
            scopeID: archive.mainEventID,
            additionalArchiveBytes: [existingArchive],
            additionalSnapshotScopeIDs: [existing.mainEventID],
            holdBootstrapResponse: true,
            loseInstallResponse: false
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlueprintInstallURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(
            baseURL: URL(string: "https://blueprint-install.invalid")!,
            urlSession: session,
            tokenStore: BlueprintInstallTokenStore()
        )
        let intentDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: intentDirectory) }
        let coordinator = BlueprintInstallationCoordinator(
            baseURL: URL(string: "https://blueprint-install.invalid")!,
            persistence: persistence,
            library: library,
            intents: BlueprintInstallationIntentStore(directoryURL: intentDirectory),
            transport: transport
        )

        let installTask = Task { try await coordinator.install(weddingInstallInput(), ownerUserID: ownerID) }
        let bootstrapStarted = await waitForBootstrapRequest()
        #expect(bootstrapStarted)
        baselineImportedWorkspace.title = "Edit made during install"
        BlueprintInstallURLProtocol.releaseBootstrapResponse.signal()

        _ = try await installTask.value
        let restoredExisting = try #require(library.workspaces.first { $0.mainEventID == existing.mainEventID })
        #expect(restoredExisting.title == "Edit made during install")
        let pending = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
        #expect(pending.contains { $0.scopeID == existing.mainEventID })
    }

    @Test("An A to B to A switch invalidates an in-flight install callback")
    func accountGenerationRejectsStaleCallback() async throws {
        let ownerID = "blueprint-owner-\(UUID().uuidString)"
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
        let intentDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: intentDirectory) }
        let input = weddingInstallInput()
        let setupDrafts = BlueprintSetupDraftStore(directoryURL: intentDirectory.appending(path: "drafts"))
        let catalogURL = try #require(Bundle(for: BlueprintInstallURLProtocol.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let entry = try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: catalogURL)).entries.first)
        try setupDrafts.save(BlueprintSetupDraft(
            ownerUserID: ownerID, entry: entry, requestID: input.requestID,
            eventName: input.mainEvent.name, startsAt: input.mainEvent.startsAt,
            timeZoneIdentifier: input.mainEvent.timeZone,
            selectedChildren: Set(input.selectedChildren.map(\.key)),
            selectedIdeas: Set(input.selectedIdeaKeys),
            confirmedDates: Dictionary(uniqueKeysWithValues: input.selectedChildren.map { ($0.key, $0.startsAt) })
        ))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let store = BlueprintInstallationIntentStore(directoryURL: intentDirectory)
        let intent = try store.prepare(
            ownerUserID: ownerID,
            requestID: input.requestID,
            requestBody: try encoder.encode(input)
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountSwitchURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(
            baseURL: URL(string: "https://account-switch.invalid")!,
            urlSession: session,
            tokenStore: BlueprintInstallTokenStore()
        )
        let coordinator = BlueprintInstallationCoordinator(
            baseURL: URL(string: "https://account-switch.invalid")!,
            persistence: persistence,
            library: library,
            intents: store,
            setupDrafts: setupDrafts,
            transport: transport
        )

        let resumeTask = Task { try await coordinator.resume(intent) }
        let statusStarted = await waitForAccountSwitchStatusRequest()
        #expect(statusStarted)
        persistence.activate(userID: "another-account", in: library)
        persistence.activate(userID: ownerID, in: library)
        AccountSwitchURLProtocol.releaseStatusRequest.signal()

        await #expect(throws: CancellationError.self) {
            try await resumeTask.value
        }
        #expect(library.workspaces.isEmpty)
        #expect(try store.pending(ownerUserID: ownerID).count == 1)
        #expect(try setupDrafts.load(ownerUserID: ownerID, catalogKey: "wedding")?.requestID == input.requestID)
    }

    @Test("Two private Cottage copies bootstrap independently and keep edits scoped across recovery")
    func twoCottageCopiesRemainIndependentAcrossRelaunch() async throws {
        let fixture = try cottageFixtureObject()
        let samples = try #require(fixture["installations"] as? [[String: Any]])
        #expect(samples.count == 2)
        let inputs = try samples.map { sample in
            let input = try #require(sample["input"] as? [String: Any])
            let mainEvent = try #require(input["mainEvent"] as? [String: Any])
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            func date(_ value: Any?) throws -> Date {
                let timestamp = try #require(value as? String)
                return try #require(formatter.date(from: timestamp))
            }
            let requestIDText = try #require(input["requestId"] as? String)
            let requestID = try #require(UUID(uuidString: requestIDText))
            let selectedChildren = try #require(input["selectedChildren"] as? [[String: Any]])
                .map { child in
                    BlueprintInstallInput.SelectedChild(
                        key: try #require(child["key"] as? String),
                        startsAt: try date(child["startsAt"])
                    )
                }
            return BlueprintInstallInput(
                requestID: requestID,
                catalogKey: try #require(input["catalogKey"] as? String),
                revision: try #require(input["revision"] as? Int),
                contentHash: try #require(input["contentHash"] as? String),
                mainEvent: .init(
                    name: try #require(mainEvent["name"] as? String),
                    startsAt: try date(mainEvent["startsAt"]),
                    timeZone: try #require(mainEvent["timeZone"] as? String)
                ),
                selectedChildren: selectedChildren,
                selectedIdeaKeys: try #require(input["selectedIdeaKeys"] as? [String]),
                capabilities: try #require(input["capabilities"] as? [String])
            )
        }
        let archives = try samples.map { sample -> (Data, WorkspaceArchiveV1) in
            let data = try JSONSerialization.data(withJSONObject: try #require(sample["archive"]))
            return (data, try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: data))
        }
        let ownerID = try #require(archives[0].1.members.first?.userID)
        let firstIdeaID = try #require(archives[0].1.ideas.first { $0.title == "Meals and groceries" }?.id)
        let expectedSecondIdeas = archives[1].1.ideas
        #expect(inputs[0].catalogKey == inputs[1].catalogKey)
        #expect(inputs[0].revision == inputs[1].revision)
        #expect(inputs[0].contentHash == inputs[1].contentHash)
        #expect(inputs[0].requestID != inputs[1].requestID)
        #expect(archives.allSatisfy { $0.1.members.first?.userID == ownerID })
        #expect(archives[0].1.mainEventID != archives[1].1.mainEventID)
        #expect(samples[0]["organizationID"] as? String != samples[1]["organizationID"] as? String)

        let storeURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        let intentDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
            try? FileManager.default.removeItem(at: intentDirectory)
        }

        let resultOverrides = try Dictionary(uniqueKeysWithValues: zip(samples, archives).map { pair in
            let (sample, archivePair) = pair
            let result: [String: Any] = [
                "installationID": try #require(sample["installationID"] as? String),
                "organizationID": try #require(sample["organizationID"] as? String),
                "scopeID": archivePair.1.mainEventID.uuidString,
            ]
            return (try #require(sample["requestID"] as? String), result)
        })
        let contentHashes = try Dictionary(uniqueKeysWithValues: zip(inputs, samples).map { pair in
            let (input, sample) = pair
            let sampleInput = try #require(sample["input"] as? [String: Any])
            let contentHash = try #require(sampleInput["contentHash"] as? String)
            return (input.requestID.uuidString.lowercased(), contentHash)
        })
        BlueprintInstallURLProtocol.configure(
            archiveBytes: archives[0].0,
            scopeID: archives[0].1.mainEventID,
            additionalArchiveBytes: archives.dropFirst().map { $0.0 },
            additionalSnapshotScopeIDs: archives.dropFirst().map { $0.1.mainEventID },
            bootstrapRequestIDs: inputs.map { $0.requestID.uuidString },
            bootstrapOnlyCommittedInstallations: true,
            loseInstallResponse: false,
            installResultOverrides: resultOverrides,
            expectedContentHashes: contentHashes
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlueprintInstallURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = PostgresSyncTransport(
            baseURL: URL(string: "https://blueprint-install.invalid")!,
            urlSession: session,
            tokenStore: BlueprintInstallTokenStore()
        )
        let account = UserAccount(
            id: ownerID, email: "riley@example.test", displayName: "Riley Example",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )

        do {
            let persistence = try WorkspacePersistenceController(storeURL: storeURL)
            let library = persistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
            library.configureViewer(account)
            let coordinator = BlueprintInstallationCoordinator(
                baseURL: URL(string: "https://blueprint-install.invalid")!,
                persistence: persistence,
                library: library,
                intents: BlueprintInstallationIntentStore(directoryURL: intentDirectory),
                transport: transport
            )

            let firstImported = try await coordinator.install(inputs[0], ownerUserID: ownerID)
            #expect(firstImported.mainEventID == archives[0].1.mainEventID)
            #expect(library.workspaces.count == 1)
            try persistence.saveChanges(in: library)
            #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).isEmpty)

            // Queue a normal edit in installation one before installation two
            // bootstraps. Its scope and frozen request must remain independent.
            let first = try #require(library.workspaces.first { $0.mainEventID == archives[0].1.mainEventID })
            let secondScopeID = archives[1].1.mainEventID
            let firstIdeaIndex = try #require(first.ideas.firstIndex { $0.id == firstIdeaID })
            var editedFirstIdea = first.ideas[firstIdeaIndex]
            editedFirstIdea.title = "Meals for the lake cottage"
            first.updateIdea(editedFirstIdea)
            first.mainEventStartsAt = first.mainEventStartsAt.addingTimeInterval(86_400)
            try persistence.saveChanges(in: library)
            let outboxBeforeSecondInstall = try ModelContext(persistence.container)
                .fetch(FetchDescriptor<PendingMutation>())
            #expect(!outboxBeforeSecondInstall.isEmpty)
            #expect(Set(outboxBeforeSecondInstall.map(\.scopeID)) == Set([first.mainEventID]))

            let secondImported = try await coordinator.install(inputs[1], ownerUserID: ownerID)
            #expect(secondImported.mainEventID == secondScopeID)
            #expect(library.workspaces.count == 2)
            #expect(Set(library.workspaces.map(\.mainEventID)) == Set(archives.map { $0.1.mainEventID }))
            #expect(BlueprintInstallURLProtocol.installRequestCount == 2)

            let secondBeforeEdit = try #require(library.workspaces.first { $0.mainEventID == archives[1].1.mainEventID })
            let secondTitle = secondBeforeEdit.title
            let secondDate = secondBeforeEdit.mainEventStartsAt
            let queued = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
            #expect(queued.count == outboxBeforeSecondInstall.count)
            #expect(Set(queued.map(\.scopeID)) == Set([first.mainEventID]))
            #expect(first.mainEventStartsAt == archives[0].1.mainEventStartsAt.addingTimeInterval(86_400))
            #expect(first.ideas.first { $0.id == firstIdeaID }?.title == "Meals for the lake cottage")
            #expect(secondBeforeEdit.title == secondTitle)
            #expect(secondBeforeEdit.mainEventStartsAt == secondDate)
            #expect(secondBeforeEdit.ideas == expectedSecondIdeas)
            let requestEncoder = JSONEncoder()
            requestEncoder.outputFormatting = [.sortedKeys]
            requestEncoder.dateEncodingStrategy = .iso8601
            let expectedRequestBodies = try inputs.map { try requestEncoder.encode($0) }
            #expect(BlueprintInstallURLProtocol.installBodies == expectedRequestBodies)
        }

        // A fresh persistence controller and coordinator model relaunch. Replaying
        // the same completed request imports both snapshots without another POST;
        // the pending first-copy edit protects its scope from the bootstrap copy.
        let relaunchedPersistence = try WorkspacePersistenceController(storeURL: storeURL)
        let relaunchedLibrary = relaunchedPersistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
        let relaunchedCoordinator = BlueprintInstallationCoordinator(
            baseURL: URL(string: "https://blueprint-install.invalid")!,
            persistence: relaunchedPersistence,
            library: relaunchedLibrary,
            intents: BlueprintInstallationIntentStore(directoryURL: intentDirectory),
            transport: transport
        )
        let outboxBeforeRecovery = try ModelContext(relaunchedPersistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
        #expect(!outboxBeforeRecovery.isEmpty)
        let recovered = try await relaunchedCoordinator.install(inputs[0], ownerUserID: ownerID)
        #expect(recovered.mainEventID == archives[0].1.mainEventID)
        #expect(BlueprintInstallURLProtocol.installRequestCount == 2)
        #expect(relaunchedLibrary.workspaces.count == 2)
        let restoredFirst = try #require(relaunchedLibrary.workspaces.first { $0.mainEventID == archives[0].1.mainEventID })
        let restoredSecond = try #require(relaunchedLibrary.workspaces.first { $0.mainEventID == archives[1].1.mainEventID })
        #expect(restoredFirst.title == archives[0].1.title)
        #expect(restoredFirst.mainEventStartsAt == archives[0].1.mainEventStartsAt.addingTimeInterval(86_400))
        #expect(restoredFirst.ideas.first { $0.id == firstIdeaID }?.title == "Meals for the lake cottage")
        #expect(restoredSecond.title == archives[1].1.title)
        #expect(restoredSecond.mainEventStartsAt == archives[1].1.mainEventStartsAt)
        #expect(restoredSecond.ideas == expectedSecondIdeas)
        let relaunchedOutbox = try ModelContext(relaunchedPersistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
        #expect(Set(relaunchedOutbox.map(\.scopeID)) == Set([archives[0].1.mainEventID]))
        #expect(relaunchedOutbox.count == outboxBeforeRecovery.count)
    }

    private func weddingFixtureData() throws -> Data {
        let bundle = Bundle(for: BlueprintInstallURLProtocol.self)
        let url = try #require(bundle.url(forResource: "wedding-install-native.v1", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func cottageFixtureObject() throws -> [String: Any] {
        let bundle = Bundle(for: BlueprintInstallURLProtocol.self)
        let url = try #require(bundle.url(forResource: "cottage-installations.v1", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func weddingInstallInput(shareToken: String? = nil) -> BlueprintInstallInput {
        BlueprintInstallInput(
            requestID: UUID(uuidString: "af08d534-8c90-4c89-bacc-0f5820bb4d0c")!,
            catalogKey: "wedding",
            revision: 1,
            contentHash: "24518a2d4795d62a7d0ed5d349cd0bb7ed7a2883a7dec7bf9c522a8e5119878a",
            mainEvent: .init(
                name: "Riley and Jordan",
                startsAt: ISO8601DateFormatter().date(from: "2027-06-15T19:00:00Z")!,
                timeZone: "America/Detroit"
            ),
            selectedChildren: [
                .init(key: "venue_visit", startsAt: ISO8601DateFormatter().date(from: "2027-06-14T20:00:00Z")!),
                .init(key: "ceremony", startsAt: ISO8601DateFormatter().date(from: "2027-06-15T19:00:00Z")!)
            ],
            selectedIdeaKeys: ["venue", "food", "photography"],
            capabilities: SyncClientCapabilities.blueprintFeatures,
            shareToken: shareToken
        )
    }

    private func waitForBootstrapRequest() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if BlueprintInstallURLProtocol.hasStartedBootstrapRequest { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func waitForAccountSwitchStatusRequest() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if AccountSwitchURLProtocol.hasStartedStatusRequest { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private struct BlueprintInstallTokenStore: SessionTokenStore {
    func read() throws -> String? { "blueprint-test-token" }
    func save(_ token: String) throws {}
    func delete() {}
}

private final class BlueprintInstallURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var archiveBytes = Data()
    private static var additionalArchiveBytes: [Data] = []
    private static var additionalSnapshotScopeIDs: [UUID] = []
    private static var bootstrapRequestIDs: [String] = []
    private static var bootstrapOnlyCommittedInstallations = false
    private static var scopeID = UUID()
    private static var installCount = 0
    private static var committedRequestIDs = Set<String>()
    private static var initialStatus: String?
    private static var loseInstallResponse = true
    private static var revokeSharedTokenAfterLostResponse = false
    private static var sharedTokenRevoked = false
    private static var holdBootstrapResponse = false
    private static var bootstrapRequestStartedValue = false
    static let releaseBootstrapResponse = DispatchSemaphore(value: 0)
    private static var lastInstallRequestIDValue: String?
    private static var lastInstallBodyValue = Data()
    private static var installBodyValues: [Data] = []
    private static var installationID = UUID()
    private static var organizationID = "wedding-org"
    private static var installResultOverrides: [String: [String: Any]] = [:]
    private static var expectedContentHashes: [String: String] = [:]

    static var installRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return installCount
    }

    static var lastInstallRequestID: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastInstallRequestIDValue
    }

    static var lastInstallBody: Data {
        lock.lock()
        defer { lock.unlock() }
        return lastInstallBodyValue
    }

    static var installBodies: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return installBodyValues
    }

    static var hasStartedBootstrapRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return bootstrapRequestStartedValue
    }

    static func configure(
        archiveBytes: Data,
        scopeID: UUID,
        initialStatus: String? = nil,
        additionalArchiveBytes: [Data] = [],
        additionalSnapshotScopeIDs: [UUID] = [],
        bootstrapRequestIDs: [String] = [],
        bootstrapOnlyCommittedInstallations: Bool = false,
        holdBootstrapResponse: Bool = false,
        loseInstallResponse: Bool = true,
        revokeSharedTokenAfterLostResponse: Bool = false,
        installResultOverrides: [String: [String: Any]] = [:],
        expectedContentHashes: [String: String] = [:]
    ) {
        lock.lock()
        self.archiveBytes = archiveBytes
        self.scopeID = scopeID
        self.additionalArchiveBytes = additionalArchiveBytes
        self.additionalSnapshotScopeIDs = additionalSnapshotScopeIDs
        self.bootstrapRequestIDs = bootstrapRequestIDs.map { $0.lowercased() }
        self.bootstrapOnlyCommittedInstallations = bootstrapOnlyCommittedInstallations
        installCount = 0
        committedRequestIDs = []
        self.initialStatus = initialStatus
        self.loseInstallResponse = loseInstallResponse
        self.revokeSharedTokenAfterLostResponse = revokeSharedTokenAfterLostResponse
        sharedTokenRevoked = false
        self.holdBootstrapResponse = holdBootstrapResponse
        bootstrapRequestStartedValue = false
        _ = releaseBootstrapResponse.wait(timeout: .now())
        lastInstallRequestIDValue = nil
        lastInstallBodyValue = Data()
        installBodyValues = []
        installationID = UUID()
        organizationID = "wedding-org"
        self.installResultOverrides = installResultOverrides
        self.expectedContentHashes = expectedContentHashes
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let url = try #require(request.url)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer blueprint-test-token")
            #expect(request.value(forHTTPHeaderField: SyncClientCapabilities.headerName) == SyncClientCapabilities.headerValue)

            let status: Int
            let payload: [String: Any]
            if request.httpMethod == "GET", url.path.hasPrefix("/api/blueprints/installations/") {
                let requestID = url.lastPathComponent.lowercased()
                Self.lock.lock()
                let isCommitted = Self.committedRequestIDs.contains(requestID)
                let initialStatus = Self.initialStatus
                let result = Self.installResultOverrides[requestID] ?? Self.installResultObject()
                Self.lock.unlock()
                if isCommitted {
                    status = 200
                    payload = ["state": "completed", "result": result]
                } else if let initialStatus {
                    status = 200
                    payload = ["state": initialStatus, "result": NSNull()]
                } else {
                    status = 404
                    payload = ["error": "NOT_FOUND"]
                }
            } else if url.path == "/api/blueprints/install" {
                #expect(request.httpMethod == "POST")
                let idempotencyKey = try #require(request.value(forHTTPHeaderField: "Idempotency-Key"))
                let bodyBytes = try requestBodyData()
                let body = try #require(try JSONSerialization.jsonObject(with: bodyBytes) as? [String: Any])
                let bodyRequestID = try #require(body["requestId"] as? String).lowercased()
                #expect(bodyRequestID == idempotencyKey)
                #expect(body["capabilities"] as? [String] == SyncClientCapabilities.blueprintFeatures)
                Self.lock.lock()
                let revoked = Self.sharedTokenRevoked && body["shareToken"] != nil
                if revoked {
                    status = 404
                    payload = ["error": "SHARED_LINK_REVOKED"]
                    Self.lock.unlock()
                } else {
                    Self.installCount += 1
                    Self.committedRequestIDs.insert(bodyRequestID)
                    Self.lastInstallRequestIDValue = idempotencyKey
                    Self.lastInstallBodyValue = bodyBytes
                    Self.installBodyValues.append(bodyBytes)
                    let loseResponse = Self.loseInstallResponse
                    if loseResponse, body["shareToken"] != nil, Self.revokeSharedTokenAfterLostResponse {
                        Self.sharedTokenRevoked = true
                    }
                    let expectedHash = Self.expectedContentHashes[bodyRequestID]
                    let installResult = Self.installResultOverrides[bodyRequestID] ?? Self.installResultObject()
                    Self.lock.unlock()
                    #expect(body["contentHash"] as? String == (expectedHash ?? "24518a2d4795d62a7d0ed5d349cd0bb7ed7a2883a7dec7bf9c522a8e5119878a"))
                    if loseResponse {
                        client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                        return
                    }
                    status = 200
                    payload = installResult
                }
            } else if url.path == "/api/sync/bootstrap" {
                Self.lock.lock()
                let archives = [Self.archiveBytes] + Self.additionalArchiveBytes
                let scopeIDs = [Self.scopeID] + Self.additionalSnapshotScopeIDs
                let requestIDs = Self.bootstrapRequestIDs
                let onlyCommitted = Self.bootstrapOnlyCommittedInstallations
                let committedRequestIDs = Self.committedRequestIDs
                let holdResponse = Self.holdBootstrapResponse
                Self.lock.unlock()
                if holdResponse {
                    Self.lock.lock()
                    Self.bootstrapRequestStartedValue = true
                    Self.lock.unlock()
                    _ = Self.releaseBootstrapResponse.wait(timeout: .now() + 10)
                }
                let visibleIndexes = archives.indices.filter { index in
                    guard onlyCommitted else { return true }
                    guard requestIDs.indices.contains(index) else { return false }
                    return committedRequestIDs.contains(requestIDs[index])
                }
                status = 200
                payload = [
                    "snapshots": visibleIndexes.map { index in
                        return [
                            "scopeID": scopeIDs[index].uuidString,
                            "payloadSchemaVersion": 1,
                            "payload": archives[index].base64EncodedString(),
                            "serverVersion": 1,
                            "updatedAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_800_000_000))
                        ]
                    },
                    "entities": []
                ]
            } else {
                Issue.record("Unexpected request \(request.httpMethod ?? "") \(url.path)")
                throw URLError(.badURL)
            }

            let response = try #require(HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func requestBodyData() throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private static func installResultObject() -> [String: Any] {
        [
            "installationID": installationID.uuidString,
            "organizationID": organizationID,
            "scopeID": scopeID.uuidString,
            "manifest": ["events": [:], "ideas": [:], "guides": [:], "personID": UUID().uuidString, "participations": [:]]
        ]
    }
}

private final class AccountSwitchURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var statusRequestStartedValue = false
    static let releaseStatusRequest = DispatchSemaphore(value: 0)

    static var hasStartedStatusRequest: Bool {
        lock.lock()
        defer { lock.unlock() }
        return statusRequestStartedValue
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.lock.lock()
        Self.statusRequestStartedValue = true
        Self.lock.unlock()
        _ = Self.releaseStatusRequest.wait(timeout: .now() + 5)
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil,
                                             headerFields: ["Content-Type": "application/json"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":"NOT_FOUND"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
