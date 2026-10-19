import Foundation
import Testing
@testable import Gatherory

@MainActor
struct BlueprintPreviewSessionTests {
    @Test("Preview swipes and discard never create a draft or change the catalog")
    func stagedChoicesStayInMemory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(entry)
        var session = makeSession(entry)
        session.decide(.pass, key: "venue")
        session.decide(.maybe, key: "flowers")
        session.decide(.love, key: "unknown")
        #expect(session.responses == ["venue": .pass, "flowers": .maybe])
        #expect(BlueprintIdeaResponsePresentation.summary(session.responses["venue"]).pass == 1)
        #expect(BlueprintIdeaResponsePresentation.summary(session.responses["flowers"]).maybe == 1)
        #expect(session.isDirty)
        #expect(try store.all(ownerUserID: "account-a").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(session.entry.contentHash == entry.contentHash)
        #expect(try encoder.encode(session.entry) == original)
        session.discardChanges()
        #expect(!session.isDirty)
        #expect(session.responses.isEmpty)
        #expect(BlueprintIdeaResponsePresentation.summary(session.responses["venue"]).unanswered == 1)
    }

    @Test("Only explicit Save Draft persists choices and applies inclusion semantics")
    func explicitSaveAndResume() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        var session = makeSession(entry)
        session.decide(.pass, key: "venue")
        session.decide(.maybe, key: "flowers")
        session.decide(.love, key: "food")
        try session.save(to: store, hasPendingInstallation: false)
        let saved = try #require(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey))
        #expect(!saved.selectedIdeas.contains("venue"))
        #expect(!saved.selectedIdeas.contains("flowers"))
        #expect(saved.selectedIdeas.contains("food"))
        #expect(saved.selectedChildren.isEmpty)
        #expect(saved.confirmedDates.isEmpty)
        #expect(saved.previewDecisions == session.responses)
        #expect(!session.isDirty)
        let resumed = makeSession(entry, draft: saved)
        #expect(resumed.responses == session.responses)
        #expect(BlueprintIdeaResponsePresentation.summary(resumed.responses["food"]).love == 1)
        #expect(!resumed.isDirty)
        #expect(resumed.draft?.requestID == saved.requestID)
    }

    @Test("Saving preview choices preserves custom content, confirmed dates, exclusions, identity and link")
    func savesWithoutReplacingSetup() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let token = String(repeating: "a", count: 64)
        let date = Date(timeIntervalSince1970: 1_800_000_000.125)
        var draft = BlueprintSetupDraft(
            ownerUserID: "account-a", entry: entry, requestID: UUID(),
            eventName: "Our private celebration", startsAt: date,
            timeZoneIdentifier: "America/Detroit", selectedChildren: ["ceremony"],
            selectedIdeas: ["venue"], confirmedDates: ["ceremony": date], shareToken: token
        )
        draft.customizations = BlueprintCustomization(ideas: [
            .init(key: "custom_snacks", title: "Late snacks", category: "food", notes: "Our list", target: .child(key: "ceremony"), configuration: ["version": .integer(1)])
        ])
        try store.save(draft)
        var session = makeSession(entry, draft: draft, token: token)
        #expect(session.content?.title == draft.eventName)
        #expect(session.content?.ideas(for: "ceremony").contains { $0.key == "custom_snacks" } == true)
        session.decide(.pass, key: "venue")
        session.decide(.maybe, key: "flowers")
        session.decide(.love, key: "custom_snacks")
        try session.save(to: store, hasPendingInstallation: false)
        let saved = try #require(try store.load(ownerUserID: "account-a", shareToken: token))
        #expect(saved.requestID == draft.requestID)
        #expect(saved.entry.contentHash == entry.contentHash)
        #expect(saved.eventName == draft.eventName)
        #expect(saved.startsAt == date)
        #expect(saved.confirmedDates == draft.confirmedDates)
        #expect(saved.selectedChildren == draft.selectedChildren)
        #expect(saved.selectedIdeas == ["custom_snacks"])
        #expect(saved.customizations == draft.customizations)
        #expect(saved.shareToken == token)
        let resumed = makeSession(entry, draft: saved, token: token)
        let resumedContent = try #require(resumed.content)
        let home = resumedContent.homeContent(responses: resumed.responses)
        #expect(home.eventIDs == [.main, .child("ceremony")])
        #expect(home.ideas(for: "ceremony").map(\.key) == ["custom_snacks"])
        #expect(resumed.draft?.confirmedDates == draft.confirmedDates)
        #expect(resumed.content?.children.count == 4)
        #expect(try store.all(ownerUserID: "account-b").isEmpty)
    }

    @Test("Pending recovery and concurrent draft replacement prevent preview overwrite")
    func blocksUnsafeSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        var first = makeSession(entry)
        first.decide(.pass, key: "venue")
        #expect(throws: BlueprintPreviewSession.SaveError.self) {
            try first.save(to: store, hasPendingInstallation: true)
        }
        #expect(try store.all(ownerUserID: "account-a").isEmpty)
        var other = makeSession(entry)
        other.decide(.love, key: "venue")
        try other.save(to: store, hasPendingInstallation: false)
        let request = try #require(other.draft?.requestID)
        #expect(throws: BlueprintPreviewSession.SaveError.self) {
            try first.save(to: store, hasPendingInstallation: false)
        }
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.requestID == request)
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.selectedIdeas.contains("venue") == true)
    }

    @Test("A mismatched account draft cannot become another account's preview session")
    func rejectsCrossAccountSeed() throws {
        let entry = try weddingEntry()
        let source = BlueprintSetupDraft(ownerUserID: "account-b", entry: entry, requestID: UUID(), eventName: "B private", startsAt: .now,
                                         timeZoneIdentifier: "UTC", selectedChildren: [], selectedIdeas: [], confirmedDates: [:], previewDecisions: ["venue": .pass])
        let session = makeSession(entry, draft: source)
        #expect(session.draft == nil)
        #expect(session.responses.isEmpty)
        #expect(session.content?.title == entry.definition.blueprint.name)
    }

    private func makeSession(_ entry: BlueprintCatalogEntry, draft: BlueprintSetupDraft? = nil, token: String? = nil) -> BlueprintPreviewSession {
        BlueprintPreviewSession(ownerID: "account-a", entry: entry, shareToken: token, savedDraft: draft, defaultEventName: "My celebration")
    }

    private func weddingEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: PreviewSessionFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PreviewSession-\(UUID().uuidString)")
    }
}

private final class PreviewSessionFixtureBundle: NSObject {}
