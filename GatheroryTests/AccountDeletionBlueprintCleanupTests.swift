import Foundation
import Testing
@testable import Gatherory

@MainActor
struct AccountDeletionBlueprintCleanupTests {
    private let accountA = "account/a + 🧩"
    private let accountB = "account/b + 🧩"

    @Test("Blueprint account purges remove corrupt local artifacts and preserve every other account byte")
    func diskPurgesAreScopedAndRetryable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = try catalogEntry()
        try seedStores(at: root, accountID: accountB, entry: entry)
        let preservedFiles = try files(at: root)
        #expect(!preservedFiles.isEmpty)

        try seedStores(at: root, accountID: accountA, entry: entry)
        // Cleanup must not depend on decoding cached records or retained bearer tokens.
        for path in try files(at: root).keys where preservedFiles[path] == nil {
            try Data("corrupt account artifact".utf8).write(to: root.appendingPathComponent(path))
        }

        for _ in 0..<2 {
            try purgeStores(at: root, accountID: accountA)
            #expect(try files(at: root) == preservedFiles)
            #expect(try BlueprintInstallationIntentStore(directoryURL: root.appendingPathComponent("intents"))
                .pending(ownerUserID: accountA).isEmpty)
            #expect(try BlueprintSetupDraftStore(directoryURL: root.appendingPathComponent("drafts"))
                .all(ownerUserID: accountA).isEmpty)
            #expect(try BlueprintLibraryCache(directoryURL: root.appendingPathComponent("library"))
                .load(ownerID: accountA).isEmpty)
            #expect(try BlueprintPersonalLibraryStore(directoryURL: root.appendingPathComponent("personal"))
                .load(ownerID: accountA).isEmpty)
        }

        #expect(try BlueprintInstallationIntentStore(directoryURL: root.appendingPathComponent("intents"))
            .pending(ownerUserID: accountB).count == 2)
        #expect(try BlueprintSetupDraftStore(directoryURL: root.appendingPathComponent("drafts"))
            .all(ownerUserID: accountB).count == 2)
        #expect(try BlueprintLibraryCache(directoryURL: root.appendingPathComponent("library"))
            .load(ownerID: accountB).count == 1)
        #expect(try BlueprintPersonalLibraryStore(directoryURL: root.appendingPathComponent("personal"))
            .load(ownerID: accountB).count == 1)
    }

    @Test("Blueprint account purges succeed when the entire local store has never existed")
    func missingStoresAreRetryable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for _ in 0..<2 { try purgeStores(at: root, accountID: accountA) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test("Blueprint account preferences clear only the deleted account and can be retried")
    func preferencesAreScopedAndRetryable() throws {
        let defaults = BlueprintCleanupMemoryDefaults()
        let visibility = BlueprintLibraryVisibilityStore(defaults: defaults)
        let collection = BlueprintLibraryCollectionPreferenceStore(defaults: defaults)
        let history = BlueprintRecentHistory(defaults: defaults)
        let hiddenA = UUID()
        let hiddenB = UUID()
        defaults.set("keep", forKey: "unrelated.preference")
        for (account, hidden) in [(accountA, hiddenA), (accountB, hiddenB)] {
            visibility.hide(hidden, ownerID: account)
            collection.save(.inProgress, ownerID: account)
            history.record("wedding", ownerID: account)
        }

        for _ in 0..<2 {
            try visibility.removeAll(accountID: accountA)
            try collection.removeAll(accountID: accountA)
            try history.removeAll(accountID: accountA)
            #expect(visibility.hiddenIDs(ownerID: accountA).isEmpty)
            #expect(collection.collection(ownerID: accountA) == nil)
            #expect(history.keys(ownerID: accountA).isEmpty)
            #expect(visibility.hiddenIDs(ownerID: accountB) == [hiddenB])
            #expect(collection.collection(ownerID: accountB) == .inProgress)
            #expect(history.keys(ownerID: accountB) == ["wedding"])
            #expect(defaults.string(forKey: "unrelated.preference") == "keep")
        }
    }

    private func seedStores(at root: URL, accountID: String, entry: BlueprintCatalogEntry) throws {
        let intents = BlueprintInstallationIntentStore(directoryURL: root.appendingPathComponent("intents"))
        for _ in 0..<2 {
            try intents.prepare(ownerUserID: accountID, requestID: UUID(), requestBody: Data("retained request".utf8))
        }
        let drafts = BlueprintSetupDraftStore(directoryURL: root.appendingPathComponent("drafts"))
        for token in [nil, String(repeating: "b7", count: 32)] as [String?] {
            try drafts.save(BlueprintSetupDraft(ownerUserID: accountID, entry: entry, requestID: UUID(),
                eventName: "Saved draft", startsAt: Date(timeIntervalSince1970: 1_811_923_200),
                timeZoneIdentifier: "America/Detroit", selectedChildren: [], selectedIdeas: [],
                confirmedDates: [:], shareToken: token))
        }
        try BlueprintLibraryCache(directoryURL: root.appendingPathComponent("library")).save([
            BlueprintUsedTemplate(installationID: UUID(), scopeID: UUID(), catalogKey: entry.catalogKey,
                revision: entry.revision, templateName: "Template", eventName: "Installed event",
                installedAt: "2026-10-20T12:00:00Z", sourceDraftData: Data("saved source".utf8))
        ], ownerID: accountID)
        try BlueprintPersonalLibraryStore(directoryURL: root.appendingPathComponent("personal")).save([
            BlueprintPersonalRecord(id: UUID(), draftVersion: 1, publishedRevision: nil,
                listedRevision: nil, catalogEntry: entry)
        ], ownerID: accountID)
    }

    private func purgeStores(at root: URL, accountID: String) throws {
        try BlueprintInstallationIntentStore(directoryURL: root.appendingPathComponent("intents"))
            .removeAll(accountID: accountID)
        try BlueprintSetupDraftStore(directoryURL: root.appendingPathComponent("drafts"))
            .removeAll(accountID: accountID)
        try BlueprintLibraryCache(directoryURL: root.appendingPathComponent("library"))
            .removeAll(accountID: accountID)
        try BlueprintPersonalLibraryStore(directoryURL: root.appendingPathComponent("personal"))
            .removeAll(accountID: accountID)
    }

    private func catalogEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: BlueprintCleanupFixtureBundle.self)
            .url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url))
            .entries.first { $0.catalogKey == "wedding" })
    }

    private func files(at root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        func read(_ directory: URL, prefix: String) throws {
            for url in try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey]) {
                let path = prefix + url.lastPathComponent
                if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    try read(url, prefix: path + "/")
                } else {
                    result[path] = try Data(contentsOf: url)
                }
            }
        }
        try read(root, prefix: "")
        return result
    }
}

private final class BlueprintCleanupFixtureBundle: NSObject {}

private final class BlueprintCleanupMemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func stringArray(forKey defaultName: String) -> [String]? { values[defaultName] as? [String] }
}
