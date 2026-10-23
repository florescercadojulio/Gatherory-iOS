import Foundation
import CryptoKit
import Testing
@testable import Gatherory

@MainActor
struct BlueprintSavedCopyResolverTests {
    @Test("Native copy snapshots remain aligned with the server round-trip fixture")
    func nativeCopySnapshotBridgeMatchesFixture() throws {
        let sourceURL = try #require(Bundle(for: SavedCopyFixtureBundle.self)
            .url(forResource: "explore-catalog.v1", withExtension: "json"))
        let source = try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: sourceURL))
        let fixtureURL = try #require(Bundle(for: SavedCopyFixtureBundle.self)
            .url(forResource: "blueprint-native-copy-snapshots.v1", withExtension: "json"))
        let fixture = try JSONDecoder().decode(NativeCopyBridgeFixture.self, from: Data(contentsOf: fixtureURL))
        #expect(fixture.formatVersion == 1)
        #expect(fixture.cases.count == 19)
        let curated = try source.entries.sorted { $0.catalogKey < $1.catalogKey }.map { entry in
            NativeCopyBridgeCase(label: "curated:\(entry.catalogKey)", source: entry,
                                 content: try BlueprintDraftContent.snapshot(of: entry))
        }
        let wedding = try weddingEntry()
        let authored = try [
            authoredEntry(from: wedding, key: "authored_single_native_bridge", singleEvent: true),
            authoredEntry(from: wedding, key: "authored_capability_native_bridge", singleEvent: false),
        ].map { entry in
            NativeCopyBridgeCase(label: "authored:\(entry.catalogKey)", source: entry,
                                 content: try BlueprintDraftContent.snapshot(of: entry))
        }
        let actual = curated + authored
        let expectedByLabel = Dictionary(uniqueKeysWithValues: fixture.cases.map { ($0.label, $0) })
        #expect(actual.map(\.label) == fixture.cases.map(\.label))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for value in actual {
            let expected = try #require(expectedByLabel[value.label])
            #expect(try encoder.encode(value.source) == encoder.encode(expected.source), Comment(rawValue: value.label))
            #expect(try encoder.encode(value.content) == encoder.encode(expected.content), Comment(rawValue: value.label))
        }
    }

    @Test("Saved-copy snapshots preserve main and child to-dos with their stable targets")
    func snapshotPreservesTodos() throws {
        let source = try weddingEntry()
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        var root = try #require(JSONSerialization.jsonObject(with: encoder.encode(source)) as? [String: Any])
        var definition = try #require(root["definition"] as? [String: Any])
        var modules = try #require(definition["modules"] as? [[String: Any]])
        modules.append([
            "key": "starter_todos", "type": "todos", "version": 1, "required": false,
            "config": ["todos": [
                ["key": "confirm-venue", "title": "Confirm venue", "target": ["kind": "main"]],
                ["key": "book-transport", "title": "Book transport", "websiteURL": "https://example.com",
                 "target": ["kind": "child", "key": "ceremony"]]
            ]]
        ])
        definition["modules"] = modules
        root["definition"] = definition
        let entry = try decoder.decode(BlueprintCatalogEntry.self, from: JSONSerialization.data(withJSONObject: root))

        let snapshot = try BlueprintDraftContent.snapshot(of: entry)
        #expect(snapshot.todos.map(\.key) == ["confirm-venue", "book-transport"])
        #expect(snapshot.todos[0].target == .main)
        #expect(snapshot.todos[1].target == .child(key: "ceremony"))
        #expect(snapshot.todos[1].websiteURL == "https://example.com")

        let decodedCopy = try decoder.decode(BlueprintCatalogEntry.self, from: encoder.encode(entry))
        #expect(try BlueprintDraftContent.snapshot(of: decodedCopy).todos == snapshot.todos)
    }

    @Test("Copy validation accepts only a validated source Explore cover on the main event")
    func curatedMainCoverCopyValidation() throws {
        let coverURL = "https://cdn.gatherory.com/explore/covers/wedding/\(String(repeating: "c", count: 64))/card.jpg"
        var source = try weddingEntry()
        var discovery = try #require(source.discovery)
        discovery.coverImageURL = coverURL
        source.discovery = discovery
        let sourceContent = try BlueprintDraftContent.snapshot(of: source)
        let copied = try weddingEntry(
            catalogKey: "private_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())",
            coverID: UUID()
        )

        #expect(try copiedSnapshotMatches(sourceContent, sourceEntry: source, entry: copied))

        var unrelatedSource = source
        var unrelatedDiscovery = try #require(unrelatedSource.discovery)
        unrelatedDiscovery.coverImageURL = "https://example.com/cover.jpg"
        unrelatedSource.discovery = unrelatedDiscovery
        #expect(try !copiedSnapshotMatches(sourceContent, sourceEntry: unrelatedSource, entry: copied))

        let childCoverCopy = try entryWithChildCover(copied, childCoverID: UUID())
        var sourceWithoutChildCoverMap = source
        var discoveryWithoutChildCoverMap = try #require(sourceWithoutChildCoverMap.discovery)
        discoveryWithoutChildCoverMap.coverImages = nil
        sourceWithoutChildCoverMap.discovery = discoveryWithoutChildCoverMap
        #expect(try !copiedSnapshotMatches(sourceContent, sourceEntry: sourceWithoutChildCoverMap, entry: childCoverCopy))
    }

    @Test("Copy validation allows materialized covers only for mapped child and idea targets")
    func curatedTargetCoverCopyValidation() throws {
        let url = "https://cdn.gatherory.com/explore/covers/wedding/\(String(repeating: "f", count: 64))/card.jpg"
        var source = try weddingEntry()
        var discovery = try #require(source.discovery)
        discovery.coverImages = BlueprintTargetCoverImages(children: ["venue_visit": url], ideas: ["flowers": url])
        source.discovery = discovery
        let snapshot = try BlueprintDraftContent.snapshot(of: source)
        #expect(snapshot.children.allSatisfy { $0.coverAssetId == nil })
        #expect(snapshot.ideas.allSatisfy { $0.coverAssetId == nil })
        var copied = try weddingEntry(catalogKey: "private_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())")
        copied = try entryWithTargetCovers(copied, childKey: "venue_visit", ideaKey: "flowers")
        let copiedSnapshot = try BlueprintDraftContent.snapshot(of: copied)
        #expect(copiedSnapshot.children.first { $0.key == "venue_visit" }?.coverAssetId != nil)
        #expect(copiedSnapshot.ideas.first { $0.key == "flowers" }?.coverAssetId != nil)
        #expect(try copiedSnapshotMatches(snapshot, sourceEntry: source, entry: copied))

        var unrelated = source
        var unrelatedDiscovery = try #require(unrelated.discovery)
        unrelatedDiscovery.coverImages = BlueprintTargetCoverImages(children: ["rehearsal": url], ideas: ["flowers": url])
        unrelated.discovery = unrelatedDiscovery
        #expect(try !copiedSnapshotMatches(snapshot, sourceEntry: unrelated, entry: copied))
    }

    @Test("Copies the original snapshot and attaches a differently keyed private catalog entry")
    func copiesOriginalSnapshotAndAttachesPrivateEntry() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        var draft = context.draft
        var overlay = BlueprintCustomization()
        try overlay.upsert(.init(key: "ceremony", title: "Our custom ceremony", purpose: "part_of_event",
                                 category: "ceremony", scheduleProposal: nil))
        draft.customizations = overlay
        try context.store.save(draft)
        let privateEntry = try weddingEntry(catalogKey: "personal_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())")
        let record = BlueprintPersonalRecord(id: UUID(), draftVersion: 1, publishedRevision: privateEntry.revision,
                                             listedRevision: nil, catalogEntry: privateEntry)
        let transport = SavedCopyFakeTransport { requestID, content in
            let persisted = try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken)
            let expectedContent = try BlueprintDraftContent.snapshot(of: context.draft.entry)
            #expect(persisted?.copyRequestID == requestID)
            #expect(content == expectedContent)
            return record
        }

        let resolved = try await resolve(draft, context: context, transport: transport)

        #expect(transport.calls.count == 1)
        #expect(resolved.entry.catalogKey == context.draft.entry.catalogKey)
        #expect(resolved.shareToken == context.draft.shareToken)
        #expect(resolved.copyEntry?.catalogKey == privateEntry.catalogKey)
        #expect(resolved.installationEntry.catalogKey == privateEntry.catalogKey)
        #expect(resolved.installationShareToken == nil)
        let savedCopy = try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken)
        #expect(savedCopy?.copyEntry?.catalogKey == privateEntry.catalogKey)
        #expect(resolved.customizations == overlay)

        let cached = try await resolve(draft, context: context, transport: transport)
        #expect(cached.copyEntry?.catalogKey == privateEntry.catalogKey)
        #expect(transport.calls.count == 1)
    }

    @Test("Persists and reuses one copy request ID after a lost network response")
    func retryUsesStableCopyRequestID() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let transport = SavedCopyFakeTransport { _, _ in throw SavedCopyTestError.networkLost }

        do {
            _ = try await resolve(context.draft, context: context, transport: transport)
            Issue.record("Expected the first copy request to fail")
        } catch SavedCopyTestError.networkLost {
        } catch {
            throw error
        }
        let savedAfterFailure = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        let stableID = try #require(savedAfterFailure.copyRequestID)
        transport.handler = { _, _ in try self.copyRecord() }

        let result = try await resolve(savedAfterFailure, context: context, transport: transport)

        #expect(transport.calls.count == 2)
        #expect(transport.calls[0].requestID == stableID)
        #expect(transport.calls[1].requestID == stableID)
        #expect(result.copyRequestID == stableID)
    }

    @Test("Rejects a wrong owner or pending installation before network access or disk writes")
    func rejectsOwnerAndPendingInstallation() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let original = try draftBytes(in: context.directory)
        let transport = SavedCopyFakeTransport { _, _ in
            Issue.record("Transport must not be called")
            throw SavedCopyTestError.networkLost
        }

        await #expect(throws: (any Error).self) {
            try await BlueprintSavedCopyResolver.resolve(
                draft: context.draft, ownerID: "account-b", store: context.store, transport: transport,
                currentOwnerID: { "account-b" }, hasPendingInstallation: { false }
            )
        }
        await #expect(throws: (any Error).self) {
            try await BlueprintSavedCopyResolver.resolve(
                draft: context.draft, ownerID: "account-a", store: context.store, transport: transport,
                currentOwnerID: { "account-a" }, hasPendingInstallation: { true }
            )
        }

        #expect(transport.calls.isEmpty)
        let after = try draftBytes(in: context.directory)
        #expect(after == original)
        #expect(context.draft.copyRequestID == nil)
    }

    @Test("Rejects a callback after the current account changes")
    func lateCallbackAfterAccountSwitchIsRejected() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        var activeOwner: String? = "account-a"
        let transport = SavedCopyFakeTransport(suspends: true)
        let task = Task {
            try await BlueprintSavedCopyResolver.resolve(
                draft: context.draft, ownerID: "account-a", store: context.store, transport: transport,
                currentOwnerID: { activeOwner }, hasPendingInstallation: { false }
            )
        }
        await transport.waitUntilCalled()
        let before = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        #expect(before.copyRequestID != nil)
        activeOwner = "account-b"
        transport.complete(with: try copyRecord())

        do {
            _ = try await task.value
            Issue.record("Expected the account switch to reject the callback")
        } catch {
        }
        let saved = try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken)
        #expect(saved?.copyEntry == nil)
    }

    @Test("Rejects a late callback after the saved draft has been replaced with another request")
    func lateCallbackAfterDraftReplacementIsRejected() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let transport = SavedCopyFakeTransport(suspends: true)
        let task = Task { try await resolve(context.draft, context: context, transport: transport) }
        await transport.waitUntilCalled()
        var replacement = context.draft
        replacement.requestID = UUID()
        replacement.eventName = "Replacement draft"
        try context.store.save(replacement)
        transport.complete(with: try copyRecord())

        do {
            _ = try await task.value
            Issue.record("Expected the replaced draft to reject the callback")
        } catch {
        }
        let saved = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        #expect(saved.requestID == replacement.requestID)
        #expect(saved.eventName == "Replacement draft")
        #expect(saved.copyEntry == nil)
    }

    @Test("Attaches the copy to the latest same-request draft while preserving edits and dates")
    func preservesEditsMadeDuringNetworkWait() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let transport = SavedCopyFakeTransport(suspends: true)
        let task = Task { try await resolve(context.draft, context: context, transport: transport) }
        await transport.waitUntilCalled()
        var edited = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        let laterDate = Date(timeIntervalSince1970: 1_900_000_000.75)
        edited.eventName = "Edited while copying"
        edited.startsAt = laterDate
        edited.timeZoneIdentifier = "UTC"
        edited.selectedChildren = ["reception"]
        edited.selectedIdeas = ["venue"]
        edited.confirmedDates = ["reception": laterDate]
        edited.previewDecisions = ["venue": .love]
        var overlay = BlueprintCustomization()
        try overlay.upsert(.init(key: "ceremony", title: "Edited overlay", purpose: "part_of_event",
                                 category: "ceremony", scheduleProposal: nil))
        let sourceIdea = try #require(try BlueprintDraftContent.snapshot(of: edited.entry).ideas.first)
        try overlay.upsert(.init(key: sourceIdea.key, title: sourceIdea.title, category: sourceIdea.category,
                                 notes: "Keep these personal notes", target: sourceIdea.target,
                                 configuration: sourceIdea.configuration))
        edited.customizations = overlay
        try context.store.save(edited)
        transport.complete(with: try copyRecord())

        let resolved = try await task.value

        #expect(resolved.eventName == "Edited while copying")
        #expect(resolved.startsAt == laterDate)
        #expect(resolved.timeZoneIdentifier == "UTC")
        #expect(resolved.selectedChildren == ["reception"])
        #expect(resolved.selectedIdeas == ["venue"])
        #expect(resolved.confirmedDates == ["reception": laterDate])
        #expect(resolved.previewDecisions == ["venue": .love])
        #expect(resolved.customizations == overlay)
        #expect(resolved.customizations?.ideas.first?.notes == "Keep these personal notes")
        #expect(resolved.copyEntry != nil)
    }

    @Test("Does not attach the returned copy if an installation becomes pending during the request")
    func pendingInstallationAfterAwaitRejectsCopy() async throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        var pending = false
        let transport = SavedCopyFakeTransport(suspends: true)
        let task = Task {
            try await BlueprintSavedCopyResolver.resolve(
                draft: context.draft, ownerID: "account-a", store: context.store, transport: transport,
                currentOwnerID: { "account-a" }, hasPendingInstallation: { pending }
            )
        }
        await transport.waitUntilCalled()
        pending = true
        transport.complete(with: try copyRecord())

        do {
            _ = try await task.value
            Issue.record("Expected the pending installation to reject the callback")
        } catch {
        }
        let saved = try #require(try context.store.load(ownerUserID: "account-a", catalogKey: "wedding", shareToken: context.draft.shareToken))
        #expect(saved.copyEntry == nil)
        #expect(saved.copyRequestID != nil)
    }

    @Test("Legacy drafts decode without the optional saved-copy fields")
    func legacyDraftDecodes() throws {
        let context = try makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let draft = context.draft
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(draft)) as? [String: Any])
        object.removeValue(forKey: "copyRequestID")
        object.removeValue(forKey: "copyEntry")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(BlueprintSetupDraft.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.copyRequestID == nil)
        #expect(decoded.copyEntry == nil)
        #expect(decoded.installationEntry.catalogKey == decoded.entry.catalogKey)
        #expect(decoded.installationShareToken == decoded.shareToken)
    }

    private func resolve(
        _ draft: BlueprintSetupDraft,
        context: Context,
        transport: SavedCopyFakeTransport
    ) async throws -> BlueprintSetupDraft {
        try await BlueprintSavedCopyResolver.resolve(
            draft: draft, ownerID: "account-a", store: context.store, transport: transport,
            currentOwnerID: { "account-a" }, hasPendingInstallation: { false }
        )
    }

    private func makeContext() throws -> Context {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BlueprintSavedCopyResolverTests-\(UUID().uuidString)")
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let draft = BlueprintSetupDraft(
            ownerUserID: "account-a", entry: try weddingEntry(), requestID: UUID(), eventName: "Wedding",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000.25), timeZoneIdentifier: "America/Detroit",
            selectedChildren: ["ceremony"], selectedIdeas: ["flowers"],
            confirmedDates: ["ceremony": Date(timeIntervalSince1970: 1_800_000_000.5)],
            shareToken: String(repeating: "a", count: 64)
        )
        try store.save(draft)
        return Context(directory: directory, store: store, draft: draft)
    }

    private func authoredEntry(
        from source: BlueprintCatalogEntry,
        key: String,
        singleEvent: Bool
    ) throws -> BlueprintCatalogEntry {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var root = try #require(JSONSerialization.jsonObject(with: encoder.encode(source)) as? [String: Any])
        root["catalogKey"] = key
        root["revision"] = 3
        root["contentHash"] = String(repeating: "0", count: 64)
        root["description"] = "A native copy bridge fixture with public instructions, ideas and notes."
        var definition = try #require(root["definition"] as? [String: Any])
        var blueprint = try #require(definition["blueprint"] as? [String: Any])
        blueprint["id"] = key
        blueprint["revision"] = 3
        blueprint["name"] = singleEvent ? "Native Single Event" : "Native Capability Matrix"
        definition["blueprint"] = blueprint
        definition["experienceDefaults"] = ["type": "custom"]
        var modules = try #require(definition["modules"] as? [[String: Any]])
        let treeIndex = try #require(modules.firstIndex { $0["type"] as? String == "experience_tree" })
        var tree = try #require(modules[treeIndex]["config"] as? [String: Any])
        tree["mainEventType"] = "custom"
        var children = try #require(tree["children"] as? [[String: Any]])
        if singleEvent {
            children = []
        } else {
            for index in children.indices {
                children[index]["coverAssetId"] = "10000000-0000-4000-8000-\(String(format: "%012d", index + 1))"
            }
        }
        tree["children"] = children
        modules[treeIndex]["config"] = tree
        let ideaIndex = try #require(modules.firstIndex { $0["type"] as? String == "ideas" })
        var ideaConfig = try #require(modules[ideaIndex]["config"] as? [String: Any])
        var ideas = try #require(ideaConfig["ideas"] as? [[String: Any]])
        for index in ideas.indices {
            if singleEvent {
                ideas[index]["target"] = ["kind": "main"]
            } else {
                ideas[index]["coverAssetId"] = "20000000-0000-4000-8000-\(String(format: "%012d", index + 1))"
            }
        }
        ideaConfig["ideas"] = ideas
        modules[ideaIndex]["config"] = ideaConfig
        if let instructionsIndex = modules.firstIndex(where: { $0["type"] as? String == "instructions" }) {
            var instructionConfig = try #require(modules[instructionsIndex]["config"] as? [String: Any])
            var sections = try #require(instructionConfig["sections"] as? [[String: Any]])
            if singleEvent {
                for index in sections.indices { sections[index]["target"] = ["kind": "main"] }
            }
            instructionConfig["sections"] = sections
            modules[instructionsIndex]["config"] = instructionConfig
        }
        if singleEvent {
            definition.removeValue(forKey: "presentation")
            modules.removeAll { $0["type"] as? String == "todos" }
        } else {
            definition["presentation"] = [
                "coverAssetId": "30000000-0000-4000-8000-000000000001",
            ]
            let childKey = try #require(children.first?["key"] as? String)
            modules.append([
                "key": "starter_todos", "type": "todos", "version": 1, "required": false,
                "config": ["todos": [
                    ["key": "confirm_main", "title": "Confirm main event", "target": ["kind": "main"]],
                    ["key": "book_child", "title": "Book child activity", "websiteURL": "https://example.com/activity",
                     "target": ["kind": "child", "key": childKey]],
                ]],
            ])
        }
        definition["modules"] = modules
        root["definition"] = definition
        if var discovery = root["discovery"] as? [String: Any] {
            discovery["summary"] = "A public native bridge fixture summary."
            root["discovery"] = discovery
        }
        return try decoder.decode(BlueprintCatalogEntry.self, from: JSONSerialization.data(withJSONObject: root))
    }

    private func weddingEntry(catalogKey: String = "wedding", coverID: UUID? = nil) throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: SavedCopyFixtureBundle.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        let response = try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url))
        let source = try #require(response.entries.first { $0.catalogKey == "wedding" })
        guard catalogKey != "wedding" else { return source }
        let identity = ExperienceBlueprintIdentity(id: catalogKey, revision: source.definition.blueprint.revision,
                                                   name: source.definition.blueprint.name)
        let definition = ExperienceBlueprintDocument(
            schema: source.definition.schema, kind: source.definition.kind,
            schemaVersion: source.definition.schemaVersion, blueprint: identity,
            experienceDefaults: source.definition.experienceDefaults, roles: source.definition.roles,
            modules: source.definition.modules,
            presentation: coverID.map { ExperiencePresentationHints(theme: nil, coverAssetID: $0, moduleOrder: nil) }
                ?? source.definition.presentation
        )
        let digest = SHA256.hash(data: Data("\(source.contentHash):\(catalogKey)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return BlueprintCatalogEntry(catalogKey: catalogKey, revision: source.revision,
                                     contentHash: digest, definition: definition,
                                     discovery: source.discovery, description: source.description)
    }

    private func entryWithChildCover(_ entry: BlueprintCatalogEntry, childCoverID: UUID) throws -> BlueprintCatalogEntry {
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        var definition = try #require(root["definition"] as? [String: Any])
        var modules = try #require(definition["modules"] as? [[String: Any]])
        let index = try #require(modules.firstIndex { $0["type"] as? String == "experience_tree" })
        var config = try #require(modules[index]["config"] as? [String: Any])
        var children = try #require(config["children"] as? [[String: Any]])
        children[0]["coverAssetId"] = childCoverID.uuidString
        config["children"] = children
        modules[index]["config"] = config
        definition["modules"] = modules
        root["definition"] = definition
        return try JSONDecoder().decode(BlueprintCatalogEntry.self, from: JSONSerialization.data(withJSONObject: root))
    }

    private func entryWithTargetCovers(_ entry: BlueprintCatalogEntry, childKey: String, ideaKey: String) throws -> BlueprintCatalogEntry {
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        var definition = try #require(root["definition"] as? [String: Any])
        var modules = try #require(definition["modules"] as? [[String: Any]])
        let treeIndex = try #require(modules.firstIndex { $0["type"] as? String == "experience_tree" })
        var treeConfig = try #require(modules[treeIndex]["config"] as? [String: Any])
        var children = try #require(treeConfig["children"] as? [[String: Any]])
        if let index = children.firstIndex(where: { $0["key"] as? String == childKey }) {
            children[index]["coverAssetId"] = UUID().uuidString
        }
        treeConfig["children"] = children
        modules[treeIndex]["config"] = treeConfig
        let ideasIndex = try #require(modules.firstIndex { $0["type"] as? String == "ideas" })
        var ideaConfig = try #require(modules[ideasIndex]["config"] as? [String: Any])
        var ideas = try #require(ideaConfig["ideas"] as? [[String: Any]])
        if let index = ideas.firstIndex(where: { $0["key"] as? String == ideaKey }) {
            ideas[index]["coverAssetId"] = UUID().uuidString
        }
        ideaConfig["ideas"] = ideas
        modules[ideasIndex]["config"] = ideaConfig
        definition["modules"] = modules
        root["definition"] = definition
        return try JSONDecoder().decode(BlueprintCatalogEntry.self, from: JSONSerialization.data(withJSONObject: root))
    }

    private func copyRecord() throws -> BlueprintPersonalRecord {
        let entry = try weddingEntry(catalogKey: "private_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())")
        return BlueprintPersonalRecord(id: UUID(), draftVersion: 1, publishedRevision: entry.revision, listedRevision: nil,
                                       catalogEntry: entry)
    }

    private func draftBytes(in directory: URL) throws -> Data {
        let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        let file = try #require(files.allObjects.compactMap { $0 as? URL }.first { $0.lastPathComponent == "draft.json" })
        return try Data(contentsOf: file)
    }
}

private struct NativeCopyBridgeFixture: Decodable {
    let formatVersion: Int
    let cases: [NativeCopyBridgeCase]
}

private struct NativeCopyBridgeCase: Codable {
    let label: String
    let source: BlueprintCatalogEntry
    let content: BlueprintDraftContent
}

private struct Context {
    let directory: URL
    let store: BlueprintSetupDraftStore
    let draft: BlueprintSetupDraft
}

@MainActor
private final class SavedCopyFakeTransport: BlueprintSavedCopyTransport {
    struct Call {
        let requestID: UUID
        let content: BlueprintDraftContent
    }

    var calls: [Call] = []
    var handler: @MainActor (UUID, BlueprintDraftContent) async throws -> BlueprintPersonalRecord
    private var continuation: CheckedContinuation<BlueprintPersonalRecord, any Error>?

    init(suspends: Bool = false,
         handler: @escaping @MainActor (UUID, BlueprintDraftContent) async throws -> BlueprintPersonalRecord = { _, _ in
             throw SavedCopyTestError.networkLost
         }) {
        self.handler = handler
        self.suspends = suspends
    }

    private let suspends: Bool

    func copyBlueprintSnapshot(requestID: UUID, content: BlueprintDraftContent) async throws -> BlueprintPersonalRecord {
        calls.append(Call(requestID: requestID, content: content))
        if suspends {
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }
        return try await handler(requestID, content)
    }

    func waitUntilCalled() async {
        for _ in 0..<100 where calls.isEmpty { await Task.yield() }
    }

    func complete(with record: BlueprintPersonalRecord) {
        continuation?.resume(returning: record)
        continuation = nil
    }
}

private enum SavedCopyTestError: Error {
    case networkLost
}

private final class SavedCopyFixtureBundle: NSObject {}
