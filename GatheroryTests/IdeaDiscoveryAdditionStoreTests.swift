import Foundation
import Testing
@testable import Gatherory

@Suite(.serialized)
@MainActor
struct IdeaDiscoveryAdditionStoreTests {
    @Test("Confirmed receipts persist by account and reject another account's receipt")
    func accountScopedReceipts() throws {
        let suiteName = "IdeaDiscoveryAdditionStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let receipt = IdeaDiscoveryAdditionReceipt(
            accountID: "account-a", sourceID: "blueprint:3:idea", workspaceID: UUID(),
            eventID: UUID(), ideaID: UUID()
        )
        let first = IdeaDiscoveryAdditionStore(ownerID: "account-a", defaults: defaults)
        first.record(receipt)
        first.record(receipt)
        #expect(first.receipts == [receipt])

        let reloaded = IdeaDiscoveryAdditionStore(ownerID: "account-a", defaults: defaults)
        #expect(reloaded.receipts == [receipt])
        reloaded.switchAccount(to: "account-b")
        #expect(reloaded.receipts.isEmpty)
        reloaded.record(receipt)
        #expect(reloaded.receipts.isEmpty)

        reloaded.switchAccount(to: "account-a")
        #expect(reloaded.receipts == [receipt])
    }

    @Test("Clearing an account removes only its local receipt collection")
    func clearAccountReceipts() throws {
        let suiteName = "IdeaDiscoveryAdditionStoreClearTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let receiptA = makeReceipt(accountID: "account-a")
        let receiptB = makeReceipt(accountID: "account-b")
        IdeaDiscoveryAdditionStore(ownerID: "account-a", defaults: defaults).record(receiptA)
        IdeaDiscoveryAdditionStore(ownerID: "account-b", defaults: defaults).record(receiptB)

        IdeaDiscoveryAdditionStore.clear(accountID: "account-a", defaults: defaults)
        #expect(IdeaDiscoveryAdditionStore(ownerID: "account-a", defaults: defaults).receipts.isEmpty)
        #expect(IdeaDiscoveryAdditionStore(ownerID: "account-b", defaults: defaults).receipts == [receiptB])
    }

    @Test("Callback generation changes across A to B to A and on same-account invalidation")
    func callbackGenerationInvalidation() throws {
        let suiteName = "IdeaDiscoveryAdditionGenerationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = IdeaDiscoveryAdditionStore(ownerID: "account-a", defaults: defaults)
        let firstA = store.callbackGeneration
        store.switchAccount(to: "account-b")
        let b = store.callbackGeneration
        #expect(firstA != b)
        store.switchAccount(to: "account-a")
        let secondA = store.callbackGeneration
        #expect(b != secondA)
        #expect(firstA != secondA)
        store.invalidateCallbacks()
        #expect(store.callbackGeneration != secondA)
    }

    @Test("A receipt shows as added only while its idea is present in the owning workspace")
    func liveIdeaMembership() throws {
        let suiteName = "IdeaDiscoveryAdditionMembershipTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ideaID = UUID()
        let workspaceID = UUID()
        let eventID = workspaceID
        let idea = PlanningIdea(id: ideaID, eventID: eventID, title: "Flowers", note: "",
                                category: .decor, submittedBy: "Planner")
        let workspace = PlanningWorkspace(mainEventID: workspaceID, title: "Event",
            mainEventStartsAt: .now, venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: "account-a", name: "Planner", participantRole: .host,
                                      initials: "P", planningPermission: .manage)],
            ideas: [idea], timeline: [], registry: [])
        let library = WorkspaceLibrary(workspaces: [workspace])
        library.configureViewer(UserAccount(id: "account-a", email: "planner@example.test",
            displayName: "Planner", role: .planner, authenticationProvider: .password, createdAt: .now))
        let entry = IdeaDiscoveryEntry(id: "source:4:flowers", sourceBlueprintId: "source",
            sourceVersion: 4, sourceTitle: "Source", creator: nil,
            idea: BlueprintCatalogIdea(key: "flowers", title: "Flowers", category: "other",
                notes: nil, target: .main, configuration: ["version": .integer(1)]),
            coverAssetId: nil, coverImageURL: nil)
        let store = IdeaDiscoveryAdditionStore(ownerID: "account-a", defaults: defaults)
        store.record(.init(accountID: "account-a", sourceID: entry.id, workspaceID: workspaceID,
                           eventID: eventID, ideaID: ideaID))

        #expect(store.isAdded(entry, in: library))
        let otherSource = IdeaDiscoveryEntry(id: "source:5:flowers", sourceBlueprintId: "source",
            sourceVersion: 5, sourceTitle: "Source", creator: nil, idea: entry.idea,
            coverAssetId: nil, coverImageURL: nil)
        #expect(!store.isAdded(otherSource, in: library))
        let emptyLibrary = WorkspaceLibrary()
        #expect(!store.isAdded(entry, in: emptyLibrary))
        #expect(store.receipts.count == 1, "A temporary workspace loading gap must not delete a valid receipt")
        #expect(store.isAdded(entry, in: library), "The badge should return when the workspace reloads")
    }

    @Test("Removing one of multiple copies leaves the source marked added")
    func oneOfMultipleCopiesRemoved() throws {
        let suiteName = "IdeaDiscoveryAdditionCopiesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let entry = makeEntry(id: "source:4:flowers")
        let first = makeWorkspace(accountID: "account-a", ideaID: UUID())
        let second = makeWorkspace(accountID: "account-a", ideaID: UUID())
        let library = WorkspaceLibrary(workspaces: [first, second])
        configure(library, accountID: "account-a")
        let store = IdeaDiscoveryAdditionStore(ownerID: "account-a", defaults: defaults)
        for workspace in [first, second] {
            let ideaID = try #require(workspace.ideas.first?.id)
            store.record(.init(accountID: "account-a", sourceID: entry.id,
                workspaceID: workspace.mainEventID, eventID: workspace.mainEventID, ideaID: ideaID))
        }
        #expect(store.isAdded(entry, in: library))
        library.remove(first)
        #expect(store.isAdded(entry, in: library))
    }

    @Test("Readable read-only copies are marked; another viewer and deleted root are not")
    func viewerAndDeletionBoundaries() throws {
        let suiteName = "IdeaDiscoveryAdditionVisibilityTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ideaID = UUID()
        let entry = makeEntry(id: "source:4:flowers")
        let workspaceID = UUID()
        let idea = PlanningIdea(id: ideaID, eventID: workspaceID, title: "Flowers", note: "",
            category: .decor, submittedBy: "Planner")
        let readableWorkspace = PlanningWorkspace(mainEventID: workspaceID, title: "Event",
            mainEventStartsAt: .now, venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: "account-a", name: "Reader", participantRole: .collaborator,
                                      initials: "R", planningPermission: .viewOnly)],
            ideas: [idea], timeline: [], registry: [])
        let library = WorkspaceLibrary(workspaces: [readableWorkspace])
        configure(library, accountID: "account-a")
        let store = IdeaDiscoveryAdditionStore(ownerID: "account-a", defaults: defaults)
        store.record(.init(accountID: "account-a", sourceID: entry.id, workspaceID: workspaceID,
                           eventID: workspaceID, ideaID: ideaID))
        #expect(store.isAdded(entry, in: library))

        configure(library, accountID: "account-b")
        #expect(!store.isAdded(entry, in: library))

        let deletedWorkspace = PlanningWorkspace(mainEventID: workspaceID, title: "Deleted",
            mainEventStartsAt: .now, venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: "account-a", name: "Reader", participantRole: .collaborator,
                                      initials: "R", planningPermission: .viewOnly)],
            ideas: [idea], timeline: [], isMainEventDeleted: true, registry: [])
        let deletedLibrary = WorkspaceLibrary(workspaces: [deletedWorkspace])
        configure(deletedLibrary, accountID: "account-a")
        #expect(!store.isAdded(entry, in: deletedLibrary))
    }

    private func makeReceipt(accountID: String) -> IdeaDiscoveryAdditionReceipt {
        .init(accountID: accountID, sourceID: "source:1:idea", workspaceID: UUID(),
              eventID: UUID(), ideaID: UUID())
    }

    private func makeEntry(id: String) -> IdeaDiscoveryEntry {
        IdeaDiscoveryEntry(id: id, sourceBlueprintId: "source", sourceVersion: 4,
            sourceTitle: "Source", creator: nil,
            idea: BlueprintCatalogIdea(key: "flowers", title: "Flowers", category: "other",
                notes: nil, target: .main, configuration: ["version": .integer(1)]),
            coverAssetId: nil, coverImageURL: nil)
    }

    private func makeWorkspace(accountID: String, ideaID: UUID) -> PlanningWorkspace {
        let workspaceID = UUID()
        let idea = PlanningIdea(id: ideaID, eventID: workspaceID, title: "Flowers", note: "",
            category: .decor, submittedBy: "Planner")
        return PlanningWorkspace(mainEventID: workspaceID, title: "Event",
            mainEventStartsAt: .now, venueName: "", location: "", planningMode: .openToIdeas,
            members: [WorkspaceMember(userID: accountID, name: "Planner", participantRole: .host,
                                      initials: "P", planningPermission: .manage)],
            ideas: [idea], timeline: [], registry: [])
    }

    private func configure(_ library: WorkspaceLibrary, accountID: String) {
        library.configureViewer(UserAccount(id: accountID, email: "\(accountID)@example.test",
            displayName: accountID, role: .planner, authenticationProvider: .password, createdAt: .now))
    }
}
