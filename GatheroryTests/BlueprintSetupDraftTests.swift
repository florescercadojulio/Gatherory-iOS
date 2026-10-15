import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintSetupDraftTests {
    @Test("A saved setup survives relaunch and reconstructs its confirmed dates and root date context")
    func roundTripAndRestoreSetupHelpers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let startsAt = Date(timeIntervalSince1970: 1_811_923_200.125)
        let ceremony = Date(timeIntervalSince1970: 1_811_923_200.125)
        let editedVenueVisit = Date(timeIntervalSince1970: 1_809_331_800.375)
        let draft = BlueprintSetupDraft(
            ownerUserID: "account-a",
            entry: entry,
            requestID: UUID(),
            eventName: "Zoë & 李 — fête 💍",
            startsAt: startsAt,
            timeZoneIdentifier: "America/Detroit",
            selectedChildren: ["ceremony", "venue_visit"],
            selectedIdeas: ["attire", "flowers"],
            confirmedDates: ["ceremony": ceremony, "venue_visit": editedVenueVisit]
        )

        try store.save(draft)
        let loadedDraft = try BlueprintSetupDraftStore(directoryURL: directory)
            .load(ownerUserID: "account-a", catalogKey: "wedding")
        let restored = try #require(loadedDraft)

        #expect(restored.ownerUserID == draft.ownerUserID)
        #expect(restored.schemaVersion == 1)
        #expect(restored.eventName == draft.eventName)
        #expect(restored.startsAt == startsAt)
        #expect(restored.timeZoneIdentifier == "America/Detroit")
        #expect(restored.entry.catalogKey == entry.catalogKey)
        #expect(restored.entry.revision == entry.revision)
        #expect(restored.entry.contentHash == entry.contentHash)
        #expect(restored.selectedChildren == draft.selectedChildren)
        #expect(restored.selectedIdeas == draft.selectedIdeas)
        #expect(restored.confirmedDates == draft.confirmedDates)

        let timeZone = try #require(TimeZone(identifier: restored.timeZoneIdentifier))
        let dateContext = BlueprintSetupDateContext(startsAt: restored.startsAt, timeZone: timeZone)
        var scheduleDraft = BlueprintScheduleDraft(confirmedDates: restored.confirmedDates)
        #expect(dateContext.startsAt == startsAt)
        #expect(dateContext.timeZoneIdentifier == "America/Detroit")
        #expect(scheduleDraft.confirmedDates == draft.confirmedDates)
        #expect(scheduleDraft.suggestions.isEmpty)

        let token = scheduleDraft.beginRefresh()
        #expect(scheduleDraft.suggestions.isEmpty)
        #expect(scheduleDraft.confirmedDates == draft.confirmedDates)
        let refreshedSuggestion = BlueprintScheduleSuggestion(
            key: "venue_visit",
            status: "suggested",
            localDateTime: "2027-05-14T13:00:00",
            candidates: [Date(timeIntervalSince1970: 1_810_000_000)]
        )
        #expect(scheduleDraft.apply([refreshedSuggestion], token: token) == true)
        #expect(scheduleDraft.suggestions["venue_visit"]?.candidates == refreshedSuggestion.candidates)
        #expect(scheduleDraft.confirmedDates["venue_visit"] == editedVenueVisit)
        #expect(scheduleDraft.confirmedDates["ceremony"] == ceremony)

        let updated = BlueprintSetupDraft(
            ownerUserID: restored.ownerUserID,
            entry: restored.entry,
            requestID: restored.requestID,
            eventName: "Zoë & 李 — fête, updated 💍",
            startsAt: restored.startsAt,
            timeZoneIdentifier: restored.timeZoneIdentifier,
            selectedChildren: ["reception"],
            selectedIdeas: ["attire"],
            confirmedDates: ["reception": Date(timeIntervalSince1970: 1_812_000_000.5)]
        )
        try store.save(updated)
        let loadedUpdate = try BlueprintSetupDraftStore(directoryURL: directory)
            .load(ownerUserID: "account-a", catalogKey: "wedding")
        let afterUpdate = try #require(loadedUpdate)
        #expect(afterUpdate.requestID == draft.requestID)
        #expect(afterUpdate.eventName == updated.eventName)
        #expect(afterUpdate.selectedChildren == updated.selectedChildren)
        #expect(afterUpdate.confirmedDates == updated.confirmedDates)
    }

    @Test("Explicitly empty selections remain empty after saving and loading")
    func emptySelectionsArePreserved() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = try weddingEntry()
        let draft = makeDraft(
            ownerUserID: "account-a",
            entry: entry,
            selectedChildren: [],
            selectedIdeas: []
        )
        let store = BlueprintSetupDraftStore(directoryURL: directory)

        try store.save(draft)
        let loadedDraft = try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)
        let restored = try #require(loadedDraft)

        #expect(restored.selectedChildren.isEmpty)
        #expect(restored.selectedIdeas.isEmpty)
    }

    @Test("Shared-link setup drafts preserve their token and remain separate from private drafts for the same blueprint")
    func sharedDraftTokenAndStorageIsolation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let token = String(repeating: "b7", count: 32)
        let anotherLinkToken = String(repeating: "c8", count: 32)
        let privateDraft = makeDraft(ownerUserID: "account-a", entry: entry, eventName: "Private")
        let sharedDraft = makeDraft(ownerUserID: "account-a", entry: entry, eventName: "Shared", shareToken: token)
        let anotherLinkDraft = makeDraft(
            ownerUserID: "account-a",
            entry: entry,
            eventName: "Another link",
            shareToken: anotherLinkToken
        )
        let otherAccountDraft = makeDraft(ownerUserID: "account-b", entry: entry, eventName: "Other account", shareToken: token)

        try store.save(privateDraft)
        try store.save(sharedDraft)
        try store.save(anotherLinkDraft)
        try store.save(otherAccountDraft)

        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.eventName == "Private")
        #expect(try store.load(ownerUserID: "account-a", shareToken: token)?.eventName == "Shared")
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey, shareToken: token)?.requestID == sharedDraft.requestID)
        #expect(try store.load(ownerUserID: "account-a", shareToken: anotherLinkToken)?.requestID == anotherLinkDraft.requestID)
        #expect(try store.load(ownerUserID: "account-b", shareToken: token)?.requestID == otherAccountDraft.requestID)
        let accountADrafts = try store.all(ownerUserID: "account-a")
        let accountBDrafts = try store.all(ownerUserID: "account-b")
        #expect(Set(accountADrafts.map(\.requestID)) == [
            privateDraft.requestID,
            sharedDraft.requestID,
            anotherLinkDraft.requestID
        ])
        #expect(accountADrafts.first(where: { $0.shareToken == token })?.eventName == "Shared")
        #expect(accountADrafts.first(where: { $0.shareToken == anotherLinkToken })?.eventName == "Another link")
        #expect(accountADrafts.allSatisfy { $0.ownerUserID == "account-a" })
        #expect(accountBDrafts.map(\.requestID) == [otherAccountDraft.requestID])
        #expect(accountBDrafts.allSatisfy { $0.ownerUserID == "account-b" })
        #expect(try store.load(ownerUserID: "account-b", shareToken: anotherLinkToken) == nil)
    }

    @Test("Older setup draft files without shareToken still decode as private drafts")
    func missingShareTokenIsBackwardCompatible() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let draft = makeDraft(ownerUserID: "account-a", entry: try weddingEntry())
        try store.save(draft)
        let file = try persistedFile(in: directory, containing: Data(draft.eventName.utf8))
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var body = try #require(envelope["draft"] as? [String: Any])
        body.removeValue(forKey: "shareToken")
        envelope["draft"] = body
        try JSONSerialization.data(withJSONObject: envelope).write(to: file, options: .atomic)

        let restored = try store.load(ownerUserID: draft.ownerUserID, catalogKey: draft.entry.catalogKey)
        #expect(try #require(restored).shareToken == nil)
    }

    @Test("Resume draft listing and lookup stay isolated across accounts and templates")
    func accountAndTemplateIsolation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let wedding = try weddingEntry()
        let birthday = try birthdayEntry()
        let weddingA = makeDraft(ownerUserID: "account-a", entry: wedding, eventName: "A wedding")
        let birthdayA = makeDraft(ownerUserID: "account-a", entry: birthday, eventName: "A birthday")
        let weddingB = makeDraft(ownerUserID: "account-b", entry: wedding, eventName: "B wedding")

        try store.save(weddingA)
        try store.save(birthdayA)
        try store.save(weddingB)

        let accountA = try store.all(ownerUserID: "account-a")
        let accountB = try store.all(ownerUserID: "account-b")
        #expect(Set(accountA.map(\.entry.catalogKey)) == [wedding.catalogKey, birthday.catalogKey])
        #expect(accountA.allSatisfy { $0.ownerUserID == "account-a" })
        #expect(accountB.map(\.eventName) == ["B wedding"])
        #expect(try store.load(ownerUserID: "account-a", catalogKey: wedding.catalogKey)?.eventName == "A wedding")
        #expect(try store.load(ownerUserID: "account-b", catalogKey: wedding.catalogKey)?.eventName == "B wedding")
        #expect(try store.load(ownerUserID: "account-a", catalogKey: birthday.catalogKey)?.eventName == "A birthday")
        #expect(try store.load(ownerUserID: "account-b", catalogKey: birthday.catalogKey) == nil)
    }

    @Test("Completion removes only the draft with the matching request ID")
    func completionIsConditionalOnRequestID() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let wedding = try weddingEntry()
        let birthday = try birthdayEntry()
        let staleRequest = makeDraft(ownerUserID: "account-a", entry: wedding, eventName: "Stale")
        let currentRequest = makeDraft(
            ownerUserID: "account-a",
            entry: wedding,
            eventName: "Current",
            requestID: UUID()
        )
        let anotherTemplate = makeDraft(ownerUserID: "account-a", entry: birthday, eventName: "Birthday")
        let otherAccount = makeDraft(ownerUserID: "account-b", entry: wedding, eventName: "Other account")
        try store.save(staleRequest)
        try store.save(currentRequest)
        try store.save(anotherTemplate)
        try store.save(otherAccount)

        try store.remove(
            ownerUserID: staleRequest.ownerUserID,
            catalogKey: wedding.catalogKey,
            requestID: staleRequest.requestID
        )
        #expect(try store.load(ownerUserID: "account-a", catalogKey: wedding.catalogKey)?.requestID == currentRequest.requestID)
        #expect(try store.load(ownerUserID: "account-a", catalogKey: birthday.catalogKey)?.requestID == anotherTemplate.requestID)
        #expect(try store.load(ownerUserID: "account-b", catalogKey: wedding.catalogKey)?.requestID == otherAccount.requestID)

        try store.remove(
            ownerUserID: currentRequest.ownerUserID,
            catalogKey: wedding.catalogKey,
            requestID: currentRequest.requestID
        )
        #expect(try store.load(ownerUserID: "account-a", catalogKey: wedding.catalogKey) == nil)
        #expect(try store.load(ownerUserID: "account-a", catalogKey: birthday.catalogKey)?.requestID == anotherTemplate.requestID)
        #expect(try store.load(ownerUserID: "account-b", catalogKey: wedding.catalogKey)?.requestID == otherAccount.requestID)
        #expect(try store.all(ownerUserID: "account-a").map(\.entry.catalogKey) == [birthday.catalogKey])
        #expect(try store.all(ownerUserID: "account-b").map(\.entry.catalogKey) == [wedding.catalogKey])
    }

    @Test("Unsupported schema versions and owner mismatches are rejected")
    func rejectsUnsupportedSchemaAndMismatchedOwner() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()

        var unsupportedVersion = makeDraft(ownerUserID: "account-a", entry: entry)
        unsupportedVersion.schemaVersion = 2
        #expect(throws: (any Error).self) {
            try store.save(unsupportedVersion)
        }

        let validDraft = makeDraft(ownerUserID: "account-a", entry: entry)
        try store.save(validDraft)
        let persistedURL = try persistedFile(in: directory, containing: Data(validDraft.ownerUserID.utf8))
        let persistedData = try Data(contentsOf: persistedURL)
        let persistedObject = try JSONSerialization.jsonObject(with: persistedData)
        var envelope = try #require(persistedObject as? [String: Any])
        var storedDraft = try #require(envelope["draft"] as? [String: Any])
        storedDraft["ownerUserID"] = "account-b"
        envelope["draft"] = storedDraft
        try JSONSerialization.data(withJSONObject: envelope).write(to: persistedURL, options: .atomic)

        #expect(throws: (any Error).self) {
            _ = try store.load(ownerUserID: validDraft.ownerUserID, catalogKey: entry.catalogKey)
        }
    }

    @Test("Corrupt persisted data is rejected without being rewritten during load")
    func corruptDataIsNotOverwrittenByLoad() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let draft = makeDraft(ownerUserID: "account-a", entry: try weddingEntry(), eventName: "Corruption target")
        try store.save(draft)

        let persistedURL = try persistedFile(in: directory, containing: Data(draft.eventName.utf8))
        let corruption = Data("not a valid encoded setup draft".utf8)
        try corruption.write(to: persistedURL, options: .atomic)

        #expect(throws: (any Error).self) {
            _ = try store.load(ownerUserID: draft.ownerUserID, catalogKey: draft.entry.catalogKey)
        }
        #expect(try Data(contentsOf: persistedURL) == corruption)
    }

    @Test("Saving setup drafts does not create installation intents in their separate store")
    func draftPersistenceDoesNotCreateInstallIntent() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let draftDirectory = root.appending(path: "setup-drafts", directoryHint: .isDirectory)
        let intentDirectory = root.appending(path: "install-intents", directoryHint: .isDirectory)
        let draft = makeDraft(ownerUserID: "account-a", entry: try weddingEntry())

        try BlueprintSetupDraftStore(directoryURL: draftDirectory).save(draft)
        let intents = try BlueprintInstallationIntentStore(directoryURL: intentDirectory)
            .pending(ownerUserID: draft.ownerUserID)

        #expect(intents.isEmpty)
        #expect(FileManager.default.fileExists(atPath: draftDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: intentDirectory.path))
    }

    private func makeDraft(
        ownerUserID: String,
        entry: BlueprintCatalogEntry,
        eventName: String = "A saved event",
        requestID: UUID = UUID(),
        selectedChildren: Set<String> = ["ceremony"],
        selectedIdeas: Set<String> = ["flowers"],
        shareToken: String? = nil
    ) -> BlueprintSetupDraft {
        BlueprintSetupDraft(
            ownerUserID: ownerUserID,
            entry: entry,
            requestID: requestID,
            eventName: eventName,
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            timeZoneIdentifier: "America/Detroit",
            selectedChildren: selectedChildren,
            selectedIdeas: selectedIdeas,
            confirmedDates: ["ceremony": Date(timeIntervalSince1970: 1_800_000_000)],
            shareToken: shareToken
        )
    }

    private func weddingEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(
            Bundle(for: SetupDraftFixtureBundle.self)
                .url(forResource: "wedding-catalog.v1", withExtension: "json")
        )
        let response = try JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url))
        return try #require(response.entries.first { $0.catalogKey == "wedding" })
    }

    private func birthdayEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(
            Bundle(for: SetupDraftFixtureBundle.self)
                .url(forResource: "curated-starters.v1", withExtension: "json")
        )
        let fixture = try JSONDecoder().decode(CuratedCatalogFixture.self, from: Data(contentsOf: url))
        return try #require(fixture.catalog.entries.first { $0.catalogKey == "birthday" })
    }

    private func persistedFile(in directory: URL, containing bytes: Data) throws -> URL {
        let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
        return try #require(
            files.allObjects.compactMap { $0 as? URL }.first { url in
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true,
                      let data = try? Data(contentsOf: url)
                else { return false }
                return data.range(of: bytes) != nil
            }
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "BlueprintSetupDraftTests-\(UUID().uuidString)")
    }
}

private final class SetupDraftFixtureBundle: NSObject {}

private struct CuratedCatalogFixture: Decodable {
    let catalog: BlueprintCatalogResponse
}
