import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct MovieNightTourCompletionTests {
    @Test("Offline removal deletes the exact renamed practice workspace and coalesces its pending creates")
    func removesOwnPracticeAndKeepsUnrelatedWorkspace() throws {
        let owner = makeAccount("tour-complete-owner")
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }
        let firstPersistence = try WorkspacePersistenceController(storeURL: storeURL)
        let firstLibrary = WorkspaceLibrary()
        firstPersistence.activate(userID: owner.id, in: firstLibrary, seedData: false)
        firstLibrary.configureViewer(owner)
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = MovieNightTourStore(defaults: defaults)
        let practice = try addPracticeWorkspace(
            owner: owner, library: firstLibrary, persistence: firstPersistence, store: store
        )
        practice.title = "My custom plan title"
        let unrelated = PlanningWorkspace.newWorkspace(
            title: "Unrelated plan", startsAt: .now, eventLocation: nil, imageData: nil, owner: owner
        )
        firstLibrary.add(unrelated, openAfterAdding: false)
        try firstPersistence.saveChanges(in: firstLibrary)

        let reopenedPersistence = try WorkspacePersistenceController(storeURL: storeURL)
        let reopenedLibrary = WorkspaceLibrary()
        reopenedPersistence.activate(userID: owner.id, in: reopenedLibrary, seedData: false)
        reopenedLibrary.configureViewer(owner)
        let restoredPractice = try #require(reopenedLibrary.workspaces.first {
            $0.mainEventID == practice.mainEventID
        })
        #expect(restoredPractice.title == "My custom plan title")
        #expect(restoredPractice.timeline.count == 1)
        let restoredSnackEvent = try #require(restoredPractice.timeline.first)
        #expect(restoredSnackEvent.parentEventID == restoredPractice.mainEventID)
        #expect(restoredSnackEvent.schedulingState == .scheduled)

        try MovieNightTourCompletion.removePracticeWorkspace(
            account: owner, workspaceID: restoredPractice.mainEventID,
            library: reopenedLibrary, persistence: reopenedPersistence, store: store
        )

        #expect(reopenedLibrary.workspaces.count == 1)
        #expect(reopenedLibrary.workspaces.first?.mainEventID == unrelated.mainEventID)
        #expect(store.progress(accountID: owner.id)?.installedWorkspaceID == restoredPractice.mainEventID)
        #expect(store.progress(accountID: owner.id)?.step == .completed)
        #expect(try reopenedPersistence.pendingScopeIDs() == [unrelated.mainEventID])

        let mutationContext = ModelContext(reopenedPersistence.container)
        let allMutations = try mutationContext.fetch(FetchDescriptor<PendingMutation>())
        let mutationsForRemovedPractice = allMutations.filter { $0.scopeID == restoredPractice.mainEventID }
        #expect(mutationsForRemovedPractice.isEmpty)
        let records = try mutationContext.fetch(FetchDescriptor<WorkspaceRecord>())
        let removedRecord = records.first(where: { $0.id == restoredPractice.mainEventID })
        #expect(removedRecord == nil)
        let retainedRecord = records.first(where: { $0.id == unrelated.mainEventID })
        #expect(retainedRecord?.ownerUserID == owner.id)

        let finalPersistence = try WorkspacePersistenceController(storeURL: storeURL)
        let finalLibrary = WorkspaceLibrary()
        finalPersistence.activate(userID: owner.id, in: finalLibrary, seedData: false)
        #expect(finalLibrary.workspaces.map(\.mainEventID) == [unrelated.mainEventID])
    }

    @Test("A server-acknowledged removal persists an account-scoped root tombstone across relaunch")
    func acknowledgedRemovalPersistsTombstoneAcrossRelaunch() async throws {
        let owner = makeAccount("tour-tombstone-owner")
        let otherAccount = makeAccount("tour-tombstone-other")
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }
        let persistence = try WorkspacePersistenceController(storeURL: storeURL)
        let library = WorkspaceLibrary()
        persistence.activate(userID: owner.id, in: library, seedData: false)
        library.configureViewer(owner)
        let store = MovieNightTourStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        let practice = try addPracticeWorkspace(owner: owner, library: library, persistence: persistence, store: store)

        let initialContext = ModelContext(persistence.container)
        let acknowledgedCreate = try #require(initialContext.fetch(FetchDescriptor<PendingMutation>()).first {
            $0.ownerUserID == owner.id && $0.scopeID == practice.mainEventID
                && $0.entityType == .workspace && $0.operation == .create
        })
        try await SwiftDataSyncStore(modelContainer: persistence.container).acknowledge([
            SyncPushResult(
                mutationID: acknowledgedCreate.id, disposition: .applied,
                serverVersion: 7, failureCode: nil
            )
        ])
        let acknowledgedRecord = try #require(ModelContext(persistence.container)
            .fetch(FetchDescriptor<WorkspaceRecord>()).first { $0.id == practice.mainEventID })
        #expect(acknowledgedRecord.serverVersion == 7)

        persistence.activate(userID: otherAccount.id, in: library, seedData: false)
        library.configureViewer(otherAccount)
        let otherWorkspace = PlanningWorkspace.newWorkspace(
            title: "Other account plan", startsAt: .now,
            eventLocation: nil, imageData: nil, owner: otherAccount
        )
        library.add(otherWorkspace)
        try persistence.saveChanges(in: library)
        let otherMutationIDs = Set(try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == otherAccount.id }
            .map(\.id))

        persistence.activate(userID: owner.id, in: library, seedData: false)
        library.configureViewer(owner)
        try MovieNightTourCompletion.removePracticeWorkspace(
            account: owner, workspaceID: practice.mainEventID,
            library: library, persistence: persistence, store: store
        )

        let afterDeleteContext = ModelContext(persistence.container)
        let remainingRecords = try afterDeleteContext.fetch(FetchDescriptor<WorkspaceRecord>())
        let practiceRecord = remainingRecords.first(where: { $0.id == practice.mainEventID })
        #expect(practiceRecord == nil)
        let outbox = try afterDeleteContext.fetch(FetchDescriptor<PendingMutation>())
        let practiceMutations = outbox.filter { $0.scopeID == practice.mainEventID }
        #expect(practiceMutations.count == 1)
        let rootTombstone = try #require(practiceMutations.first)
        #expect(rootTombstone.ownerUserID == owner.id)
        #expect(rootTombstone.entityType == .workspace)
        #expect(rootTombstone.operation == .delete)
        #expect(rootTombstone.baseVersion == 7)
        #expect(rootTombstone.payload.isEmpty)
        let survivingOtherMutations = Set(outbox.filter { $0.ownerUserID == otherAccount.id }.map(\.id))
        #expect(survivingOtherMutations == otherMutationIDs)

        let relaunchedPersistence = try WorkspacePersistenceController(storeURL: storeURL)
        let relaunchedLibrary = WorkspaceLibrary()
        relaunchedPersistence.activate(userID: otherAccount.id, in: relaunchedLibrary, seedData: false)
        #expect(relaunchedLibrary.workspaces.map(\.mainEventID) == [otherWorkspace.mainEventID])
        let relaunchedOtherIDs = Set(try ModelContext(relaunchedPersistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == otherAccount.id }
            .map(\.id))
        #expect(relaunchedOtherIDs == otherMutationIDs)

        relaunchedPersistence.activate(userID: owner.id, in: relaunchedLibrary, seedData: false)
        #expect(relaunchedLibrary.workspaces.isEmpty)
        let relaunchedTombstone = try ModelContext(relaunchedPersistence.container)
            .fetch(FetchDescriptor<PendingMutation>())
            .first(where: { $0.id == rootTombstone.id })
        #expect(relaunchedTombstone?.ownerUserID == owner.id)
        #expect(relaunchedTombstone?.operation == .delete)
    }

    @Test("A failed scoped delete restores library order, selection, receipt, records, and outbox")
    func failedRemovalRestoresEverything() throws {
        let owner = makeAccount("tour-complete-rollback")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner.id)
        library.configureViewer(owner)
        let store = MovieNightTourStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        let practice = try addPracticeWorkspace(owner: owner, library: library, persistence: persistence, store: store)
        let other = PlanningWorkspace.newWorkspace(
            title: "Other local workspace", startsAt: .now, eventLocation: nil, imageData: nil, owner: owner
        )
        library.add(other, openAfterAdding: false)
        try persistence.saveChanges(in: library)
        let originalIDs = library.workspaces.map(\.mainEventID)
        let originalSelectionID = library.selectedWorkspace?.mainEventID
        let originalMutationIDs = Set(try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>()).map(\.id))
        other.mainEventStartsAt = Date(timeIntervalSinceReferenceDate: .infinity)

        #expect(throws: EncodingError.self) {
            try MovieNightTourCompletion.removePracticeWorkspace(
                account: owner, workspaceID: practice.mainEventID,
                library: library, persistence: persistence, store: store
            )
        }

        #expect(library.workspaces.map(\.mainEventID) == originalIDs)
        #expect(library.selectedWorkspace?.mainEventID == originalSelectionID)
        #expect(library.workspaces.first === other)
        #expect(library.workspaces.last === practice)
        #expect(store.progress(accountID: owner.id)?.step == .schedule)
        let context = ModelContext(persistence.container)
        let records = try context.fetch(FetchDescriptor<WorkspaceRecord>())
        #expect(records.count == 2)
        let afterMutationIDs = Set(try context.fetch(FetchDescriptor<PendingMutation>()).map(\.id))
        #expect(afterMutationIDs == originalMutationIDs)
    }

    @Test("Removal rejects a foreign account or a workspace ID that does not match its receipt")
    func removalRequiresActiveAccountAndExactReceiptID() throws {
        let owner = makeAccount("tour-complete-receipt-owner")
        let otherAccount = makeAccount("tour-complete-receipt-other")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: owner.id)
        library.configureViewer(owner)
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = MovieNightTourStore(defaults: defaults)
        let practice = try addPracticeWorkspace(owner: owner, library: library, persistence: persistence, store: store)
        let wrongReceiptID = UUID()
        store.recordPreviewUsed(
            accountID: otherAccount.id, installedWorkspaceID: practice.mainEventID,
            snackIdeaID: UUID(), eventIdeaID: UUID()
        )

        #expect(throws: MovieNightTourCompletion.RemovalError.self) {
            try MovieNightTourCompletion.removePracticeWorkspace(
                account: owner, workspaceID: wrongReceiptID,
                library: library, persistence: persistence, store: store
            )
        }
        #expect(library.workspaces.contains(where: { $0.mainEventID == practice.mainEventID }))

        let replacementReceiptID = UUID()
        store.restart(
            accountID: owner.id, installedWorkspaceID: replacementReceiptID,
            snackIdeaID: UUID(), eventIdeaID: UUID()
        )
        #expect(throws: MovieNightTourCompletion.RemovalError.self) {
            try MovieNightTourCompletion.removePracticeWorkspace(
                account: owner, workspaceID: practice.mainEventID,
                library: library, persistence: persistence, store: store
            )
        }
        #expect(library.workspaces.contains(where: { $0.mainEventID == practice.mainEventID }))

        #expect(throws: MovieNightTourCompletion.RemovalError.self) {
            try MovieNightTourCompletion.removePracticeWorkspace(
                account: otherAccount, workspaceID: practice.mainEventID,
                library: library, persistence: persistence, store: store
            )
        }
        #expect(library.workspaces.contains(where: { $0.mainEventID == practice.mainEventID }))
        #expect(store.progress(accountID: otherAccount.id)?.installedWorkspaceID == practice.mainEventID)
        #expect(store.progress(accountID: owner.id)?.installedWorkspaceID == replacementReceiptID)
    }

    @Test("Removal requires the receipt owner to be the current active host with manage permission")
    func removalRequiresActiveHostAuthority() throws {
        let account = makeAccount("tour-complete-authority")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: account.id)
        library.configureViewer(account)
        let store = MovieNightTourStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        let collaborator = WorkspaceMember(
            userID: account.id, name: account.displayName, participantRole: .collaborator,
            initials: "MH", planningPermission: .manage
        )
        let plan = PlanningWorkspace(
            title: "Movie Night", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [collaborator], ideas: [], timeline: [], registry: []
        )
        library.add(plan)
        try persistence.saveChanges(in: library)
        store.recordPreviewUsed(
            accountID: account.id, installedWorkspaceID: plan.mainEventID,
            snackIdeaID: UUID(), eventIdeaID: UUID()
        )

        #expect(throws: MovieNightTourCompletion.RemovalError.self) {
            try MovieNightTourCompletion.removePracticeWorkspace(
                account: account, workspaceID: plan.mainEventID,
                library: library, persistence: persistence, store: store
            )
        }
        #expect(library.workspaces.first === plan)
        #expect(store.progress(accountID: account.id)?.step == .previewUsed)
        #expect(try persistence.pendingScopeIDs() == [plan.mainEventID])
    }

    @Test("A host whose current event permission is view only cannot remove the practice workspace")
    func removalRejectsViewOnlyHost() throws {
        let account = makeAccount("tour-complete-view-only")
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: account.id)
        library.configureViewer(account)
        let store = MovieNightTourStore(defaults: try #require(UserDefaults(suiteName: suiteName)))
        let viewOnlyHost = WorkspaceMember(
            userID: account.id, name: account.displayName, participantRole: .host,
            initials: "MH", planningPermission: .viewOnly
        )
        let plan = PlanningWorkspace(
            title: "Movie Night", mainEventStartsAt: .now, venueName: "", location: "",
            planningMode: .openToIdeas, members: [viewOnlyHost], ideas: [], timeline: [], registry: []
        )
        library.add(plan)
        try persistence.saveChanges(in: library)
        store.recordPreviewUsed(
            accountID: account.id, installedWorkspaceID: plan.mainEventID,
            snackIdeaID: UUID(), eventIdeaID: UUID()
        )
        let originalMutationIDs = Set(try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>()).map(\.id))

        #expect(throws: MovieNightTourCompletion.RemovalError.self) {
            try MovieNightTourCompletion.removePracticeWorkspace(
                account: account, workspaceID: plan.mainEventID,
                library: library, persistence: persistence, store: store
            )
        }
        #expect(library.workspaces.first === plan)
        #expect(store.progress(accountID: account.id)?.step == .previewUsed)
        let currentMutationIDs = Set(try ModelContext(persistence.container)
            .fetch(FetchDescriptor<PendingMutation>()).map(\.id))
        #expect(currentMutationIDs == originalMutationIDs)
    }

    private var suiteName: String { "MovieNightTourCompletionTests-\(UUID().uuidString)" }

    private func makeAccount(_ id: String) -> UserAccount {
        UserAccount(
            id: id, email: "\(id)@example.test", displayName: "Movie Host",
            role: .planner, authenticationProvider: .password, createdAt: .now
        )
    }

    private func addPracticeWorkspace(
        owner: UserAccount,
        library: WorkspaceLibrary,
        persistence: WorkspacePersistenceController,
        store: MovieNightTourStore
    ) throws -> PlanningWorkspace {
        let bundled = try BundledMovieNightTour.makeBundledWorkspace(account: owner)
        library.configureViewer(owner)
        library.add(bundled.planningWorkspace)
        try persistence.saveChanges(in: library)
        store.recordPreviewUsed(
            accountID: owner.id,
            installedWorkspaceID: bundled.planningWorkspace.mainEventID,
            snackIdeaID: bundled.snackIdeaID,
            eventIdeaID: bundled.eventIdeaID
        )
        store.advance(accountID: owner.id, to: .schedule)
        return bundled.planningWorkspace
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gatherory-movie-tour-completion-\(UUID().uuidString).sqlite")
    }

    private func removeStoreFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
    }
}
