import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintCustomizationTests {
    @Test("Customization defaults decode to an empty version one value")
    func customizationDefaults() throws {
        let decoded = try JSONDecoder().decode(BlueprintCustomization.self, from: Data("{}".utf8))
        #expect(decoded.version == 1)
        #expect(decoded.children.isEmpty)
        #expect(decoded.ideas.isEmpty)
        #expect(decoded.isEmpty)
    }

    @Test("Customization overlays replace in place, append additions, and leave the source entry immutable")
    func overlaysPreserveOrderAndSource() throws {
        let entry = try weddingEntry()
        let source = try sourceConfigs(entry)
        let originalEntry = entry
        var customization = BlueprintCustomization()
        try customization.upsert(child("ceremony", title: "Updated ceremony"))
        try customization.upsert(child(" custom_gathering ", title: "  Family gathering  "))
        try customization.upsert(idea("flowers", title: "Updated flowers"))
        try customization.upsert(idea("custom_transport", title: "Guest transport", category: "other", notes: "  Bring a pass  "))

        let applied = try customization.applying(to: entry)

        #expect(applied.tree.children.map(\.key) == source.tree.children.map(\.key) + ["custom_gathering"])
        #expect(applied.tree.children.first { $0.key == "ceremony" }?.title == "Updated ceremony")
        #expect(applied.ideas.ideas.map(\.key) == source.ideas.ideas.map(\.key) + ["custom_transport"])
        #expect(applied.ideas.ideas.first { $0.key == "flowers" }?.title == "Updated flowers")
        #expect(applied.ideas.ideas.first { $0.key == "custom_transport" }?.notes == "Bring a pass")
        #expect(applied.ideas.categoryOrder.last == "other")
        #expect(entry.catalogKey == originalEntry.catalogKey)
        #expect(entry.revision == originalEntry.revision)
        #expect(entry.contentHash == originalEntry.contentHash)
        #expect(try sourceConfigs(entry).tree == source.tree)
        #expect(try sourceConfigs(entry).ideas == source.ideas)
    }

    @Test("Customization validates counts, categories, Unicode scalar lengths, keys, and targets")
    func validatesEffectiveData() throws {
        let entry = try weddingEntry()
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            var invalidTitle = BlueprintCustomization()
            try invalidTitle.upsert(child("extra", title: String(repeating: "é", count: 121)))
        }

        var invalidIdea = BlueprintCustomization()
        try invalidIdea.upsert(idea("extra_idea", title: "Missing target", target: .child(key: "missing")))
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            try invalidIdea.applying(to: entry)
        }

        let source = try sourceConfigs(entry)
        var tooManyChildren = BlueprintCustomization(children: (0..<(51 - source.tree.children.count)).map {
            child("added_\($0)", title: "Added \($0)")
        })
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            try tooManyChildren.applying(to: entry)
        }
        tooManyChildren = BlueprintCustomization(children: [child("main", title: "Reserved")])
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            try tooManyChildren.applying(to: entry)
        }
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            var invalidKey = BlueprintCustomization()
            try invalidKey.upsert(child("Bad-Key", title: "Invalid key"))
        }
        let tooManyIdeas = BlueprintCustomization(ideas: (0..<(101 - source.ideas.ideas.count)).map {
            idea("added_idea_\($0)", title: "Added idea \($0)")
        })
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            try tooManyIdeas.applying(to: entry)
        }
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            var invalidCategory = BlueprintCustomization()
            try invalidCategory.upsert(idea("unknown_category", title: "Unknown", category: "music"))
        }
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            var invalidNotes = BlueprintCustomization()
            try invalidNotes.upsert(idea("long_notes", title: "Long notes", notes: String(repeating: "é", count: 2_001)))
        }
        let duplicateKeys = BlueprintCustomization(children: [
            child("duplicate", title: "First"), child("duplicate", title: "Second")
        ])
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            try duplicateKeys.applying(to: entry)
        }
    }

    @Test("Setup draft customization round-trips with account isolation and old drafts decode without it")
    func draftPersistenceCompatibilityAndIsolation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = try weddingEntry()
        var customization = BlueprintCustomization()
        try customization.upsert(child("custom_ceremony", title: "Personal ceremony"))
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let accountA = makeDraft(owner: "account-a", entry: entry, customizations: customization)
        let accountB = makeDraft(owner: "account-b", entry: entry)
        try store.save(accountA)
        try store.save(accountB)

        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.customizations == customization)
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.confirmedDates == accountA.confirmedDates)
        #expect(try store.load(ownerUserID: "account-b", catalogKey: entry.catalogKey)?.customizations == nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var oldDraftObject = try #require(JSONSerialization.jsonObject(with: encoder.encode(accountB)) as? [String: Any])
        oldDraftObject.removeValue(forKey: "customizations")
        let oldDraftData = try JSONSerialization.data(withJSONObject: oldDraftObject)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decodedOldDraft = try decoder.decode(BlueprintSetupDraft.self, from: oldDraftData)
        #expect(decodedOldDraft.customizations == nil)
    }

    @Test("Invalid customizations fail draft save before creating or replacing persisted data")
    func invalidDraftIsNotWritten() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = try weddingEntry()
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let valid = makeDraft(owner: "account-a", entry: entry)
        try store.save(valid)
        let fileURL = try persistedFile(in: directory)
        let originalBytes = try Data(contentsOf: fileURL)

        let invalid = makeDraft(
            owner: "account-a",
            entry: entry,
            customizations: BlueprintCustomization(children: [child("main", title: "Reserved")])
        )
        #expect(throws: BlueprintSetupDraftStore.StoreError.invalidCustomization) {
            try store.save(invalid)
        }
        #expect(try Data(contentsOf: fileURL) == originalBytes)

        var envelope = try #require(JSONSerialization.jsonObject(with: originalBytes) as? [String: Any])
        var storedDraft = try #require(envelope["draft"] as? [String: Any])
        storedDraft["customizations"] = [
            "version": 1,
            "children": [["key": "main", "title": "Reserved", "purpose": "part_of_event", "category": "ceremony"]],
            "ideas": []
        ]
        envelope["draft"] = storedDraft
        let invalidBytes = try JSONSerialization.data(withJSONObject: envelope)
        try invalidBytes.write(to: fileURL, options: .atomic)
        #expect(throws: BlueprintSetupDraftStore.StoreError.invalidCustomization) {
            _ = try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)
        }
        #expect(try Data(contentsOf: fileURL) == invalidBytes)
    }

    @Test("Customization fields survive encoding and exact installation intent recovery")
    func customizationIsInEncodedIntentBody() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var customization = BlueprintCustomization()
        try customization.upsert(child("custom_ceremony", title: "Ceremony"))
        try customization.upsert(idea("custom_flowers", title: "Flowers", target: .child(key: "custom_ceremony")))
        let input = BlueprintInstallInput(
            requestID: UUID(), catalogKey: "wedding", revision: 1,
            contentHash: String(repeating: "a", count: 64),
            mainEvent: .init(name: "Wedding", startsAt: Date(timeIntervalSince1970: 1_800_000_000), timeZone: "America/Detroit"),
            selectedChildren: [], selectedIdeaKeys: [], capabilities: [],
            customizations: customization
        )
        let body = try JSONEncoder().encode(input)
        let intentStore = BlueprintInstallationIntentStore(directoryURL: directory)
        try intentStore.prepare(ownerUserID: "account-a", requestID: input.requestID, requestBody: body)
        let recovered = try #require(intentStore.pending(ownerUserID: "account-a").first)

        #expect(recovered.requestBody == body)
        let request = try #require(JSONSerialization.jsonObject(with: recovered.requestBody) as? [String: Any])
        let encodedCustomizations = try #require(request["customizations"] as? [String: Any])
        #expect(encodedCustomizations["version"] as? Int == 1)
        #expect((encodedCustomizations["children"] as? [[String: Any]])?.first?["key"] as? String == "custom_ceremony")
        let encodedIdea = try #require((encodedCustomizations["ideas"] as? [[String: Any]])?.first)
        let target = try #require(encodedIdea["target"] as? [String: Any])
        #expect(target["kind"] as? String == "child")
        #expect(target["key"] as? String == "custom_ceremony")

        let mainTarget = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(BlueprintTarget.main)) as? [String: Any])
        #expect(mainTarget["kind"] as? String == "main")
        #expect(mainTarget["key"] == nil)
        var legacyInput = input
        legacyInput.customizations = nil
        let legacyBody = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyInput)) as? [String: Any])
        #expect(legacyBody["customizations"] == nil)
    }

    private func child(_ key: String, title: String) -> BlueprintCatalogChild {
        BlueprintCatalogChild(
            key: key, title: title, purpose: "part_of_event", category: "ceremony",
            scheduleProposal: BlueprintScheduleProposal(anchor: "main_start", dayOffset: 0, localTime: "15:00")
        )
    }

    private func idea(
        _ key: String,
        title: String,
        category: String = "flowers",
        target: BlueprintTarget = .main,
        notes: String? = nil
    ) -> BlueprintCatalogIdea {
        BlueprintCatalogIdea(
            key: key, title: title, category: category, notes: notes, target: target,
            configuration: ["version": .integer(1)]
        )
    }

    private func makeDraft(
        owner: String,
        entry: BlueprintCatalogEntry,
        customizations: BlueprintCustomization? = nil
    ) -> BlueprintSetupDraft {
        BlueprintSetupDraft(
            ownerUserID: owner, entry: entry, requestID: UUID(), eventName: "Saved event",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000), timeZoneIdentifier: "America/Detroit",
            selectedChildren: [], selectedIdeas: [],
            confirmedDates: ["ceremony": Date(timeIntervalSince1970: 1_810_000_000)],
            customizations: customizations
        )
    }

    private func weddingEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: BlueprintCustomizationFixtureBundle.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
    }

    private func sourceConfigs(
        _ entry: BlueprintCatalogEntry
    ) throws -> (tree: BlueprintExperienceTreeConfig, ideas: BlueprintIdeasConfig) {
        let modules = entry.definition.modules
        let tree = try #require(modules.first(where: { $0.type == "experience_tree" })?
            .decodeConfiguration(BlueprintExperienceTreeConfig.self))
        let ideas = try #require(modules.first(where: { $0.type == "ideas" })?
            .decodeConfiguration(BlueprintIdeasConfig.self))
        return (tree, ideas)
    }

    private func persistedFile(in directory: URL) throws -> URL {
        let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
        return try #require(enumerator.allObjects.compactMap { $0 as? URL }.first {
            $0.lastPathComponent == "draft.json"
        })
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "BlueprintCustomizationTests-\(UUID().uuidString)")
    }
}

private final class BlueprintCustomizationFixtureBundle: NSObject {}
