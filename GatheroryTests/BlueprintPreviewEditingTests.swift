import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct BlueprintPreviewEditingTests {
    @Test("Explicit main-date confirmation survives save and resume without treating name edits as confirmation")
    func mainDateConfirmationPersists() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        var session = makeSession(entry)
        var values = session.mainEventValues
        values.name = "Renamed event"
        try session.editMainEvent(values)
        try session.save(to: store, hasPendingInstallation: false)
        #expect(session.draft?.mainDateConfirmed != true)
        values.startsAt = Date(timeIntervalSince1970: 1_900_000_000)
        try session.editMainEvent(values, confirmsDate: true)
        session.discardChanges()
        try session.save(to: store, hasPendingInstallation: false)
        #expect(session.draft?.mainDateConfirmed != true)
        try session.editMainEvent(values, confirmsDate: true)
        try session.save(to: store, hasPendingInstallation: false)
        let saved = try #require(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey))
        #expect(saved.mainDateConfirmed == true)
        #expect(saved.startsAt == values.startsAt)
        let resumed = makeSession(entry, draft: saved)
        #expect(resumed.draft?.mainDateConfirmed == true)
        #expect(resumed.mainEventValues.startsAt == values.startsAt)
        let data = try JSONEncoder().encode(saved)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "mainDateConfirmed")
        let decoded = try JSONDecoder().decode(BlueprintSetupDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.mainDateConfirmed == nil)
        #expect(decoded.requestID == saved.requestID)
        #expect(decoded.selectedChildren == saved.selectedChildren)
        var changed = makeSession(entry, draft: saved)
        values.startsAt = values.startsAt.addingTimeInterval(86_400)
        try changed.editMainEvent(values)
        try changed.save(to: store, hasPendingInstallation: false)
        #expect(changed.draft?.mainDateConfirmed == false)
    }
    @Test("Child, idea, and main event edits stay staged until explicitly saved")
    func editsStayInMemoryUntilSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let source = try encoder.encode(entry)
        var session = makeSession(entry)
        let startsAt = Date(timeIntervalSince1970: 1_900_000_000)

        try session.editChild(child("welcome_party", title: "Welcome party"))
        try session.editIdea(idea("welcome_gifts", title: "Welcome gifts", target: .child(key: "welcome_party")))
        try session.editMainEvent(.init(name: "Our celebration", startsAt: startsAt, timeZoneIdentifier: "America/Detroit"))

        #expect(session.isDirty)
        #expect(session.customizations.children.map(\.key) == ["welcome_party"])
        #expect(session.customizations.ideas.map(\.key) == ["welcome_gifts"])
        #expect(session.mainEventValues == .init(name: "Our celebration", startsAt: startsAt, timeZoneIdentifier: "America/Detroit"))
        #expect(try store.all(ownerUserID: "account-a").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try encoder.encode(session.entry) == source)

        session.discardChanges()
        #expect(!session.isDirty)
        #expect(session.customizations.isEmpty)
        #expect(session.mainEventValues.name == "My celebration")
        #expect(session.content?.children.map(\.key) == ["venue_visit", "rehearsal", "ceremony", "reception"])
        #expect(try store.all(ownerUserID: "account-a").isEmpty)
    }

    @Test("Discard restores the saved content overlay and saved main event values")
    func discardRestoresSavedOverlay() throws {
        let entry = try weddingEntry()
        let startsAt = Date(timeIntervalSince1970: 1_800_000_000)
        var savedCustomization = BlueprintCustomization()
        try savedCustomization.upsert(child("ceremony", title: "Personal ceremony"))
        try savedCustomization.upsert(idea("venue", title: "Our venue", target: .main))
        let draft = BlueprintSetupDraft(
            ownerUserID: "account-a", entry: entry, requestID: UUID(), eventName: "Saved celebration",
            startsAt: startsAt, timeZoneIdentifier: "America/Detroit", selectedChildren: ["ceremony"],
            selectedIdeas: ["venue"], confirmedDates: ["ceremony": startsAt], customizations: savedCustomization
        )
        var session = makeSession(entry, draft: draft)

        try session.editChild(child("ceremony", title: "Edited ceremony"))
        try session.editIdea(idea("venue", title: "Edited venue", target: .main))
        try session.editMainEvent(.init(name: "Unsaved event name", startsAt: startsAt.addingTimeInterval(86_400), timeZoneIdentifier: "UTC"))
        #expect(session.isDirty)
        #expect(session.content?.children.first(where: { $0.key == "ceremony" })?.title == "Edited ceremony")
        #expect(session.content?.ideas.first(where: { $0.key == "venue" })?.title == "Edited venue")

        session.discardChanges()

        #expect(!session.isDirty)
        #expect(session.customizations == savedCustomization)
        #expect(session.mainEventValues == .init(name: "Saved celebration", startsAt: startsAt, timeZoneIdentifier: "America/Detroit"))
        #expect(session.content?.children.first(where: { $0.key == "ceremony" })?.title == "Personal ceremony")
        #expect(session.content?.ideas.first(where: { $0.key == "venue" })?.title == "Our venue")
        #expect(session.draft?.confirmedDates == ["ceremony": startsAt])
    }

    @Test("Explicit save preserves identity and content without selecting unanswered additions")
    func saveEditsPreservingSetupState() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let token = String(repeating: "b", count: 64)
        let confirmed = Date(timeIntervalSince1970: 1_800_000_000.25)
        let draft = BlueprintSetupDraft(
            ownerUserID: "account-a", entry: entry, requestID: UUID(), eventName: "Original celebration",
            startsAt: confirmed, timeZoneIdentifier: "America/Detroit", selectedChildren: ["ceremony"],
            selectedIdeas: ["venue"], confirmedDates: ["ceremony": confirmed], shareToken: token
        )
        try store.save(draft)
        var session = makeSession(entry, draft: draft, token: token)
        let newStartsAt = Date(timeIntervalSince1970: 1_900_000_000.5)

        try session.editChild(child("welcome_party", title: "Welcome party"))
        try session.editIdea(idea("welcome_gifts", title: "Welcome gifts", target: .child(key: "welcome_party")))
        try session.editMainEvent(.init(name: "Updated celebration", startsAt: newStartsAt, timeZoneIdentifier: "UTC"))
        let beforeSave = try #require(try store.load(ownerUserID: "account-a", shareToken: token))
        #expect(beforeSave.requestID == draft.requestID)
        #expect(beforeSave.eventName == draft.eventName)
        #expect(beforeSave.selectedChildren == draft.selectedChildren)
        #expect(beforeSave.selectedIdeas == draft.selectedIdeas)
        #expect(beforeSave.customizations == nil)
        #expect(session.isDirty)

        try session.save(to: store, hasPendingInstallation: false)

        let saved = try #require(try store.load(ownerUserID: "account-a", shareToken: token))
        #expect(saved.requestID == draft.requestID)
        #expect(saved.shareToken == token)
        #expect(saved.entry.contentHash == entry.contentHash)
        #expect(saved.eventName == "Updated celebration")
        #expect(saved.startsAt == newStartsAt)
        #expect(saved.timeZoneIdentifier == "UTC")
        #expect(saved.selectedChildren.isEmpty)
        #expect(saved.selectedIdeas.isEmpty)
        #expect(saved.confirmedDates == draft.confirmedDates)
        #expect(saved.confirmedDates["welcome_party"] == nil)
        #expect(saved.customizations?.children.map(\.key) == ["welcome_party"])
        #expect(saved.customizations?.ideas.map(\.key) == ["welcome_gifts"])
        #expect(!session.isDirty)
    }

    @Test("Invalid edits and pending installation do not persist staged changes")
    func invalidAndPendingChangesAreNotSaved() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        var session = makeSession(entry)

        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            try session.editChild(child("main", title: "Reserved"))
        }
        #expect(throws: BlueprintCustomization.CustomizationError.self) {
            try session.editIdea(idea("invalid_idea", title: "Missing child", target: .child(key: "missing")))
        }
        #expect(throws: BlueprintPreviewSession.SaveError.self) {
            try session.editMainEvent(.init(name: "  ", startsAt: .now, timeZoneIdentifier: "UTC"))
        }
        #expect(session.customizations.isEmpty)
        #expect(!session.isDirty)

        try session.editChild(child("welcome_party", title: "Welcome party"))
        #expect(throws: BlueprintPreviewSession.SaveError.self) {
            try session.save(to: store, hasPendingInstallation: true)
        }
        #expect(try store.all(ownerUserID: "account-a").isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(session.isDirty)
    }

    @Test("An edit session ignores another account's saved draft and writes only to its owner")
    func crossAccountDraftIsolation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let foreign = BlueprintSetupDraft(
            ownerUserID: "account-b", entry: entry, requestID: UUID(), eventName: "Private to B",
            startsAt: .now, timeZoneIdentifier: "UTC", selectedChildren: [], selectedIdeas: [],
            confirmedDates: [:], customizations: BlueprintCustomization(ideas: [idea("private_idea", title: "Private idea")])
        )
        try store.save(foreign)
        var session = makeSession(entry, draft: foreign)
        try session.editIdea(idea("account_a_idea", title: "Account A idea"))

        try session.save(to: store, hasPendingInstallation: false)

        #expect(session.draft?.ownerUserID == "account-a")
        #expect(try store.load(ownerUserID: "account-b", catalogKey: entry.catalogKey)?.requestID == foreign.requestID)
        #expect(try store.load(ownerUserID: "account-b", catalogKey: entry.catalogKey)?.customizations == foreign.customizations)
        #expect(try store.load(ownerUserID: "account-a", catalogKey: entry.catalogKey)?.customizations?.ideas.map(\.key) == ["account_a_idea"])
    }

    @Test("Install selections match Home, including custom targets and reconsidered Loves")
    func installationMatchesHome() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        var session = makeSession(entry)
        try session.editChild(child("welcome_party", title: "Welcome party"))
        try session.editIdea(idea("gifts", title: "Gifts", target: .child(key: "welcome_party")))
        try session.editIdea(idea("snacks", title: "Snacks", target: .child(key: "welcome_party")))
        session.decide(.love, key: "venue")
        session.decide(.love, key: "gifts")
        session.decide(.maybe, key: "snacks")
        session.decide(.pass, key: "flowers")
        try session.save(to: store, hasPendingInstallation: false)
        let saved = try #require(session.draft)
        let content = try #require(session.content)
        let home = content.homeContent(responses: session.responses)
        #expect(saved.selectedIdeas == Set(home.ideas.map(\.key)))
        #expect(saved.selectedChildren == Set(home.children.map(\.key)))
        #expect(saved.selectedIdeas == ["venue", "gifts"])
        #expect(saved.selectedChildren == ["welcome_party"])
        let requestID = saved.requestID
        session.decide(.maybe, key: "gifts")
        session.decide(.pass, key: "venue")
        try session.save(to: store, hasPendingInstallation: false)
        #expect(session.draft?.selectedIdeas.isEmpty == true)
        #expect(session.draft?.selectedChildren.isEmpty == true)
        #expect(session.draft?.requestID == requestID)
        #expect(session.content?.ideas.contains { $0.key == "gifts" } == true)
        #expect(try store.all(ownerUserID: "another-account").isEmpty)
    }

    @Test("Create Workspace copies content but never reuses an installation request or confirmed dates")
    func freshWorkspaceCopy() throws {
        let entry = try weddingEntry()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let source = BlueprintSetupDraft(ownerUserID: "a", entry: entry, requestID: UUID(), eventName: "Cottage",
            startsAt: date, timeZoneIdentifier: "America/Detroit", selectedChildren: ["ceremony"],
            selectedIdeas: ["venue"], confirmedDates: ["ceremony": date], previewDecisions: ["venue": .love],
            mainDateConfirmed: true)
        let copy = try source.freshWorkspaceCopy(ownerID: "a")
        #expect(copy.requestID != source.requestID)
        #expect(copy.confirmedDates.isEmpty)
        #expect(copy.mainDateConfirmed == false)
        #expect(copy.entry.catalogKey == source.entry.catalogKey)
        #expect(copy.entry.contentHash == source.entry.contentHash)
        #expect(copy.entry.revision == source.entry.revision)
        #expect(copy.previewDecisions == source.previewDecisions)
        #expect(copy.selectedIdeas == source.selectedIdeas)
        #expect(source.confirmedDates == ["ceremony": date])
        let route = try #require(BlueprintLibrarySetupRoute.workspace(from: copy, ownerID: "a"))
        #expect(route.createsWorkspace)
        #expect(route.installationOwnerID == "a")
        #expect(route.catalogKey == source.entry.catalogKey)
        #expect(route.shareToken == source.shareToken)
        #expect(BlueprintLibrarySetupRoute.workspace(from: copy, ownerID: "b") == nil)
        #expect(throws: BlueprintSetupDraftStore.StoreError.self) { try source.freshWorkspaceCopy(ownerID: "b") }
    }

    @Test("Create Workspace resolves the latest saved edits instead of a stale receipt snapshot")
    func latestSavedWorkspaceSource() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let source = BlueprintSetupDraft(ownerUserID: "a", entry: entry, requestID: UUID(), eventName: "Original",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000), timeZoneIdentifier: "America/Detroit",
            selectedChildren: [], selectedIdeas: ["venue"], confirmedDates: [:], previewDecisions: ["venue": .love])
        var receipt = BlueprintUsedTemplate(installationID: UUID(), scopeID: UUID(), catalogKey: entry.catalogKey,
            revision: entry.revision, templateName: "Wedding", eventName: "Existing workspace",
            installedAt: "2026-10-19T12:00:00Z", sourceDraftData: try JSONEncoder().encode(source))
        var latest = try source.freshWorkspaceCopy(ownerID: "a")
        latest.eventName = "Latest saved name"
        var overlay = BlueprintCustomization()
        try overlay.upsert(idea("venue", title: "Latest saved venue"))
        latest.customizations = overlay
        try store.save(latest)
        let resolved = try #require(try receipt.workspaceDraft(ownerID: "a", store: store))
        #expect(resolved.requestID == latest.requestID)
        #expect(resolved.eventName == latest.eventName)
        #expect(resolved.customizations?.ideas.first?.title == "Latest saved venue")
        #expect(try receipt.previewSource(ownerID: "a")?.eventName == "Original")
        #expect(throws: BlueprintLibraryCache.StoreError.self) {
            try receipt.workspaceDraft(ownerID: "b", store: store)
        }
        // Once an installation consumes its working draft, the saved library source forks again.
        receipt.sourceDraftData = try JSONEncoder().encode(latest)
        try store.remove(ownerUserID: "a", catalogKey: entry.catalogKey, requestID: latest.requestID, shareToken: nil)
        let next = try #require(try receipt.workspaceDraft(ownerID: "a", store: store))
        #expect(next.requestID != latest.requestID)
        #expect(next.eventName == latest.eventName)
        #expect(next.customizations?.ideas.first?.title == "Latest saved venue")
        #expect(next.confirmedDates.isEmpty)
        #expect(next.mainDateConfirmed == false)
        #expect(receipt.eventName == "Existing workspace")
        #expect(try store.load(ownerUserID: "a", catalogKey: entry.catalogKey)?.requestID == next.requestID)
    }

    @Test("An installed card resolves its offline blueprint source, not a live workspace or a newer revision")
    func installedBlueprintSource() throws {
        let entry = try weddingEntry()
        let source = BlueprintSetupDraft(ownerUserID: "a", entry: entry, requestID: UUID(), eventName: "Saved blueprint",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000), timeZoneIdentifier: "America/Detroit",
            selectedChildren: [], selectedIdeas: ["venue"], confirmedDates: [:], previewDecisions: ["venue": .love])
        var receipt = BlueprintUsedTemplate(installationID: UUID(), scopeID: UUID(), catalogKey: entry.catalogKey,
            revision: entry.revision, templateName: "Wedding", eventName: "Workspace",
            installedAt: "2026-10-19T12:00:00Z", sourceDraftData: try JSONEncoder().encode(source))
        let loaded = try receipt.previewSource(ownerID: "a")
        let restored = try #require(loaded)
        #expect(restored.requestID == source.requestID)
        #expect(restored.entry.contentHash == entry.contentHash)
        #expect(restored.previewDecisions == source.previewDecisions)
        #expect(throws: BlueprintLibraryCache.StoreError.self) { try receipt.previewSource(ownerID: "b") }
        let wrongRevision = BlueprintUsedTemplate(installationID: receipt.id, scopeID: receipt.scopeID,
            catalogKey: receipt.catalogKey, revision: receipt.revision + 1, templateName: receipt.templateName,
            eventName: receipt.eventName, installedAt: receipt.installedAt, sourceDraftData: receipt.sourceDraftData)
        #expect(throws: BlueprintLibraryCache.StoreError.self) { try wrongRevision.previewSource(ownerID: "a") }
        receipt.sourceDraftData = nil
        #expect(try receipt.previewSource(ownerID: "a") == nil)
    }

    @Test("Reusing a completed shared copy no longer depends on its revocable entry link")
    func copiedBlueprintDetachesEntryLink() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory)
        let entry = try weddingEntry()
        let token = String(repeating: "ab", count: 32)
        let source = BlueprintSetupDraft(ownerUserID: "a", entry: entry, requestID: UUID(), eventName: "Shared copy",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000), timeZoneIdentifier: "America/Detroit",
            selectedChildren: [], selectedIdeas: ["venue"], confirmedDates: [:], shareToken: token)
        let receipt = BlueprintUsedTemplate(installationID: UUID(), scopeID: UUID(), catalogKey: entry.catalogKey,
            revision: entry.revision, templateName: "Wedding", eventName: "Workspace",
            installedAt: "2026-10-19T12:00:00Z", sourceDraftData: try JSONEncoder().encode(source))
        var edited = try source.freshWorkspaceCopy(ownerID: "a")
        edited.eventName = "Latest local edit"
        try store.save(edited)
        let resolved = try #require(try receipt.workspaceDraft(ownerID: "a", store: store))
        #expect(resolved.shareToken == nil)
        #expect(resolved.eventName == edited.eventName)
        #expect(resolved.requestID == edited.requestID)
        #expect(try store.load(ownerUserID: "a", catalogKey: entry.catalogKey, shareToken: token) == nil)
        #expect(try store.load(ownerUserID: "a", catalogKey: entry.catalogKey)?.requestID == edited.requestID)
        #expect(try receipt.previewSource(ownerID: "a")?.shareToken == token)
    }

    @Test("Editing an installed blueprint forks a reusable local draft without changing a workspace or outbox")
    func editInstalledBlueprintIndependently() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintSetupDraftStore(directoryURL: directory.appending(path: "drafts"))
        let cache = BlueprintLibraryCache(directoryURL: directory.appending(path: "history"))
        let entry = try weddingEntry()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let owner = UserAccount(id: "a", email: "a@example.test", displayName: "A", role: .planner,
                                authenticationProvider: .password, createdAt: date)
        let workspace = PlanningWorkspace.newWorkspace(title: "Independent workspace", startsAt: date,
            eventLocation: nil, imageData: nil, owner: owner)
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "a")
        library.configureViewer(owner)
        library.add(workspace)
        library.open(workspace)
        try persistence.saveChanges(in: library)
        let before = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
        let payloads = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.payload) })
        let source = BlueprintSetupDraft(ownerUserID: "a", entry: entry, requestID: UUID(), eventName: "Blueprint name",
            startsAt: date, timeZoneIdentifier: "America/Detroit", selectedChildren: [], selectedIdeas: ["venue", "custom"],
            confirmedDates: ["ceremony": date], customizations: BlueprintCustomization(ideas: [
                idea("venue", title: "Original venue"), idea("custom", title: "Keep this custom idea")
            ]), previewDecisions: ["venue": .love, "custom": .love], mainDateConfirmed: true)
        let receipt = BlueprintUsedTemplate(installationID: UUID(), scopeID: workspace.mainEventID,
            catalogKey: entry.catalogKey, revision: entry.revision, templateName: "Wedding", eventName: workspace.title,
            installedAt: "2026-10-19T12:00:00Z", sourceDraftData: try JSONEncoder().encode(source))
        try cache.record(receipt, ownerID: "a")
        var session = BlueprintPreviewSession(ownerID: "a", entry: entry, shareToken: nil,
            savedDraft: nil, defaultEventName: "Fallback", sourceDraft: source)
        #expect(session.draft == nil)
        #expect(!session.isDirty)
        #expect(try store.all(ownerUserID: "a").isEmpty)
        try session.editIdea(idea("venue", title: "Changed venue"))
        session.discardChanges()
        #expect(!session.isDirty)
        #expect(session.content?.ideas.first { $0.key == "venue" }?.title == "Original venue")
        try session.editIdea(idea("venue", title: "Changed venue"))
        session.decide(.love, key: "venue")
        try session.save(to: store, hasPendingInstallation: false)
        let saved = try #require(session.draft)
        #expect(saved.requestID != source.requestID)
        #expect(saved.confirmedDates.isEmpty)
        #expect(saved.mainDateConfirmed != true)
        #expect(saved.customizations?.ideas.contains { $0.key == "custom" } == true)
        try cache.updateSource(saved, installationID: receipt.id, ownerID: "a")
        let updated = try #require(try cache.load(ownerID: "a").first)
        #expect(updated.scopeID == receipt.scopeID)
        #expect(updated.installationID == receipt.installationID)
        #expect(updated.installedAt == receipt.installedAt)
        let updatedSource = try updated.previewSource(ownerID: "a")
        let retained = try #require(updatedSource)
        try store.remove(ownerUserID: "a", catalogKey: entry.catalogKey, requestID: saved.requestID)
        let reopened = BlueprintPreviewSession(ownerID: "a", entry: entry, shareToken: nil,
            savedDraft: nil, defaultEventName: "Fallback", sourceDraft: retained)
        #expect(!reopened.isDirty)
        #expect(reopened.content?.ideas.first { $0.key == "venue" }?.title == "Changed venue")
        #expect(source.customizations?.ideas.first { $0.key == "venue" }?.title == "Original venue")
        #expect(workspace.title == "Independent workspace")
        #expect(library.selectedWorkspaceID == workspace.mainEventID)
        let after = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>())
        #expect(Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0.payload) }) == payloads)
        #expect(throws: BlueprintLibraryCache.StoreError.self) {
            try cache.updateSource(saved, installationID: receipt.id, ownerID: "b")
        }
    }

    private func makeSession(_ entry: BlueprintCatalogEntry, draft: BlueprintSetupDraft? = nil, token: String? = nil) -> BlueprintPreviewSession {
        BlueprintPreviewSession(ownerID: "account-a", entry: entry, shareToken: token, savedDraft: draft, defaultEventName: "My celebration")
    }

    private func child(_ key: String, title: String) -> BlueprintCatalogChild {
        BlueprintCatalogChild(key: key, title: title, purpose: "part_of_event", category: "ceremony", scheduleProposal: nil)
    }

    private func idea(_ key: String, title: String, target: BlueprintTarget = .main) -> BlueprintCatalogIdea {
        BlueprintCatalogIdea(key: key, title: title, category: "flowers", notes: nil, target: target, configuration: ["version": .integer(1)])
    }

    private func weddingEntry() throws -> BlueprintCatalogEntry {
        let url = try #require(Bundle(for: PreviewEditingFixtureBundle.self).url(forResource: "wedding-catalog.v1", withExtension: "json"))
        return try #require(JSONDecoder().decode(BlueprintCatalogResponse.self, from: Data(contentsOf: url)).entries.first)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PreviewEditing-\(UUID().uuidString)")
    }
}

private final class PreviewEditingFixtureBundle: NSObject {}
