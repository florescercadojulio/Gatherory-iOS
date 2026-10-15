import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct CuratedBlueprintTests {
    @Test("Explore discovers all three server starters through categories and search")
    func catalogDiscovery() async throws {
        let fixture = try fixtureObject()
        let catalog = try JSONDecoder().decode(BlueprintCatalogResponse.self, from: JSONSerialization.data(withJSONObject: fixture["catalog"]!))
        #expect(Set(catalog.entries.map(\.catalogKey)) == ["wedding", "birthday", "thanksgiving"])
        let birthday = try #require(catalog.entries.first { $0.catalogKey == "birthday" })
        let thanksgiving = try #require(catalog.entries.first { $0.catalogKey == "thanksgiving" })
        #expect(birthday.browseCategories == [.birthdays])
        #expect(birthday.matches(query: "birthday cake"))
        #expect(thanksgiving.browseCategories == [.holidays])
        #expect(thanksgiving.matches(query: "friendsgiving dinner"))
        let model = BlueprintDiscoveryModel(ownerID: "")
        await model.load { catalog }
        #expect(model.entries.count == 3)
    }

    @Test("Curated starter imports preserve dates, hierarchy, host controls and offline edits",
          arguments: ["birthday", "thanksgiving"])
    func nativeImport(catalogKey: String) throws {
        let fixture = try fixtureObject()
        let samples = try #require(fixture["samples"] as? [[String: Any]])
        let sample = try #require(samples.first { $0["catalogKey"] as? String == catalogKey })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let schedule = try decoder.decode(BlueprintScheduleResponse.self, from: JSONSerialization.data(withJSONObject: sample["schedule"]!))
        let preview = try decoder.decode(BlueprintPreviewResponse.self, from: JSONSerialization.data(withJSONObject: sample["preview"]!))
        var draft = BlueprintScheduleDraft()
        let token = draft.beginRefresh()
        draft.apply(schedule.suggestions, token: token)
        #expect(draft.confirmedDates.isEmpty)
        for child in preview.plan.children { draft.confirm(key: child.sourceKey, date: child.startsAt) }
        let refresh = draft.beginRefresh()
        draft.apply(schedule.suggestions, token: refresh)
        let first = try #require(preview.plan.children.first)
        #expect(draft.confirmedDates[first.sourceKey] == first.startsAt)
        #expect(first.startsAt != schedule.suggestions.first?.candidates.first)

        let bytes = try JSONSerialization.data(withJSONObject: sample["archive"]!)
        let archive = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: bytes)
        let ownerID = try #require(archive.members.first?.userID)
        let account = UserAccount(id: ownerID, email: "riley@example.test", displayName: "Riley Example",
                                  role: .planner, authenticationProvider: .password, createdAt: .now)
        let storeURL = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }
        do {
            let persistence = try WorkspacePersistenceController(storeURL: storeURL)
            let library = persistence.restoreLibrary(seedData: false, ownerUserID: ownerID)
            library.configureViewer(account)
            try persistence.applyBootstrap([
                RemoteWorkspaceSnapshot(scopeID: archive.mainEventID, payload: bytes, serverVersion: 1, updatedAt: .now)
            ], to: library)
            #expect(library.workspaces.count == 1)
            let workspace = try #require(library.workspaces.first)
            #expect(workspace.mainEventID == archive.mainEventID)
            #expect(workspace.canManageMainEvent && workspace.showsPlanningInterface)
            #expect(workspace.experienceConfiguration?.experienceType == (catalogKey == "birthday" ? "birthday" : "holiday"))
            #expect(workspace.guides == archive.guides)
            #expect(workspace.timeline.count == preview.plan.children.count)
            #expect(workspace.timeline.allSatisfy { $0.parentEventID == workspace.mainEventID })
            #expect(workspace.timeline.map(\.scheduledAt) == archive.timeline.map(\.scheduledAt))
            #expect(workspace.ideas.count == preview.plan.ideas.count)
            #expect(workspace.ideas.allSatisfy { $0.status == .new })
            try persistence.saveChanges(in: library)
            #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).isEmpty)
            workspace.title = "Edited \(catalogKey)"
            try persistence.saveChanges(in: library)
            #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMutation>()).count == 1)
        }
        let reopened = try WorkspacePersistenceController(storeURL: storeURL)
        let library = reopened.restoreLibrary(seedData: false, ownerUserID: ownerID)
        let workspace = try #require(library.workspaces.first)
        #expect(workspace.title == "Edited \(catalogKey)")
        #expect(workspace.guides == archive.guides)
        #expect(workspace.experienceConfiguration == archive.experienceConfiguration)
        #expect(try ModelContext(reopened.container).fetch(FetchDescriptor<PendingMutation>()).count == 1)
    }

    private func fixtureObject() throws -> [String: Any] {
        let url = try #require(Bundle(for: CuratedFixtureBundle.self).url(forResource: "curated-starters.v1", withExtension: "json"))
        return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}

private final class CuratedFixtureBundle: NSObject {}
