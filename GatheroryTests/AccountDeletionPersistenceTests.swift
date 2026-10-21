import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct AccountDeletionPersistenceTests {
    @Test("Account purge isolates identical scopes, entity IDs and envelopes across all namespaces", arguments: [true, false])
    func purgeOnlyConfirmedAccount(active: Bool) throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = LocalGuestProfile(displayName: "Retained guest")
        let deletedAccount = "account-delete"
        let otherAccount = "account-keep"
        let owners: [String?] = [deletedAccount, otherAccount, profile.storageID, nil]
        let entityID = UUID()
        let envelopeID = UUID()
        let context = ModelContext(persistence.container)
        context.autosaveEnabled = false
        let source = PlanningWorkspace.newWorkspace(
            title: "Shared scope", startsAt: .now, eventLocation: nil, imageData: nil
        )
        let scopeID = source.mainEventID
        let payload = try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: source))
        var files: [URL] = []
        for (index, owner) in owners.enumerated() {
            let file = directory.appending(path: "\(index).jpg")
            try Data([UInt8(index)]).write(to: file)
            files.append(file)
            context.insert(WorkspaceRecord(id: scopeID, payload: payload, sortOrder: 0, ownerUserID: owner))
            context.insert(PendingMutation(scopeID: scopeID, entityType: .todo, entityID: entityID,
                operation: .update, payload: Data([UInt8(index)]), ownerUserID: owner))
            context.insert(SyncCheckpoint(scopeID: scopeID, cursor: "cursor-\(index)", ownerUserID: owner))
            context.insert(AppliedSyncEnvelope(id: envelopeID, scopeID: scopeID, ownerUserID: owner))
            context.insert(RemoteEntityVersionRecord(scopeID: scopeID, entityType: .todo,
                entityID: entityID, serverVersion: index + 1, ownerUserID: owner))
            context.insert(PendingMediaTransfer(scopeID: scopeID, entityID: entityID,
                localFileURL: file, contentType: "image/jpeg", ownerUserID: owner))
        }
        context.insert(LocalGuestWorkspaceImportReceipt(guestProfileID: profile.id,
            accountID: deletedAccount, workspaceIDsPayload: try JSONEncoder().encode([scopeID])))
        context.insert(LocalGuestWorkspaceImportReceipt(guestProfileID: UUID(),
            accountID: otherAccount, workspaceIDsPayload: try JSONEncoder().encode([scopeID])))
        try context.save()

        let activeID = active ? deletedAccount : otherAccount
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: activeID)
        let visible = try #require(library.workspaces.first)
        let generation = persistence.activeUserGeneration
        try persistence.purgeLocalData(accountID: deletedAccount, from: library)
        try persistence.purgeLocalData(accountID: deletedAccount, from: library)

        let verification = ModelContext(persistence.container)
        let retainedOwners = Set(owners.dropFirst())
        #expect(Set(try verification.fetch(FetchDescriptor<WorkspaceRecord>()).map(\.ownerUserID)) == retainedOwners)
        #expect(Set(try verification.fetch(FetchDescriptor<PendingMutation>()).map(\.ownerUserID)) == retainedOwners)
        let checkpoints = try verification.fetch(FetchDescriptor<SyncCheckpoint>())
        #expect(Set(checkpoints.map(\.ownerUserID)) == retainedOwners)
        #expect(checkpoints.first { $0.ownerUserID == otherAccount }?.cursor == "cursor-1")
        #expect(Set(try verification.fetch(FetchDescriptor<AppliedSyncEnvelope>()).map(\.ownerUserID)) == retainedOwners)
        let versions = try verification.fetch(FetchDescriptor<RemoteEntityVersionRecord>())
        #expect(Set(versions.map(\.ownerUserID)) == retainedOwners)
        #expect(versions.first { $0.ownerUserID == otherAccount }?.serverVersion == 2)
        #expect(Set(try verification.fetch(FetchDescriptor<PendingMediaTransfer>()).map(\.ownerUserID)) == retainedOwners)
        #expect(try verification.fetch(FetchDescriptor<LocalGuestWorkspaceImportReceipt>()).map(\.accountID) == [otherAccount])
        #expect(try persistence.guestImportAccountID(profile) == nil)
        #expect(!FileManager.default.fileExists(atPath: files[0].path))
        #expect(files.dropFirst().allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        if active {
            #expect(library.workspaces.isEmpty)
            #expect(persistence.activeUserID == deletedAccount)
            #expect(persistence.activeUserGeneration != generation)
            // Normal logout must still activate/restore the retained legacy
            // namespace rather than save this empty graph over its archives.
            persistence.activate(userID: nil, in: library)
            #expect(library.workspaces.map(\.mainEventID) == [scopeID])
            try persistence.saveChanges(in: library)
            #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<WorkspaceRecord>()).count == 3)
        } else {
            #expect(library.workspaces.first === visible)
            #expect(persistence.activeUserID == otherAccount)
            #expect(persistence.activeUserGeneration == generation)
        }
    }

    @Test("Inactive deletion preserves a guest or legacy library and its unsaved changes", arguments: [true, false])
    func inactiveDeletionPreservesPendingSave(guest: Bool) async throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let profile = LocalGuestProfile(displayName: "Local planner")
        let library = persistence.restoreLibrary(seedData: false)
        if guest { try persistence.activateLocalGuest(profile, in: library) }
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Before", startsAt: .now, eventLocation: nil, imageData: nil
        )
        library.add(workspace)
        try persistence.saveChanges(in: library)
        persistence.startObserving(library)
        // Consume the guest activation's observation suppression before checking
        // an ordinary editor change, just as the app does after its handoff.
        workspace.title = "Observation warmup"
        for _ in 0..<10 { await Task.yield() }
        try persistence.saveChanges(in: library)
        workspace.title = "Unsaved retained edit"
        for _ in 0..<100 {
            if persistence.hasUnsavedLocalChanges { break }
            await Task.yield()
        }
        #expect(persistence.hasUnsavedLocalChanges)
        let generation = persistence.activeUserGeneration
        try persistence.purgeLocalData(accountID: "deleted-inactive-account", from: library)
        #expect(persistence.hasUnsavedLocalChanges)
        #expect(persistence.activeUserGeneration == generation)
        #expect(persistence.activeUserID == (guest ? profile.storageID : nil))
        #expect(library.workspaces.first === workspace)
        try persistence.saveChanges(in: library)
        let context = ModelContext(persistence.container)
        let record = try #require(context.fetch(FetchDescriptor<WorkspaceRecord>()).first)
        #expect(try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: record.payload).title == "Unsaved retained edit")
    }

    @Test("Deletion preserves media shared with a retained namespace and tolerates missing files")
    func sharedAndMissingMedia() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "shared.jpg")
        try Data([1, 2, 3]).write(to: file)
        let context = ModelContext(persistence.container)
        context.autosaveEnabled = false
        for owner in ["deleted", "retained"] {
            context.insert(PendingMediaTransfer(scopeID: UUID(), entityID: UUID(), localFileURL: file,
                contentType: "image/jpeg", ownerUserID: owner))
        }
        context.insert(PendingMediaTransfer(scopeID: UUID(), entityID: UUID(),
            localFileURL: directory.appending(path: "already-removed.jpg"), contentType: "image/jpeg", ownerUserID: "deleted"))
        try context.save()
        try persistence.purgeLocalData(accountID: "deleted", from: library)
        let verification = ModelContext(persistence.container)
        #expect(try verification.fetch(FetchDescriptor<PendingMediaTransfer>()).map(\.ownerUserID) == ["retained"])
        #expect(try Data(contentsOf: file) == Data([1, 2, 3]))
    }

    @Test("Media I/O failure retains durable cleanup rows and can be retried")
    func mediaFailureRollsBackDeletion() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "deleted")
        let workspace = PlanningWorkspace.newWorkspace(title: "Delete later", startsAt: .now,
            eventLocation: nil, imageData: nil)
        library.add(workspace)
        try persistence.saveChanges(in: library)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appending(path: "not-a-directory")
        try Data([1]).write(to: blocker)
        let mediaFile = blocker.appending(path: "image.jpg")
        let context = ModelContext(persistence.container)
        context.insert(PendingMediaTransfer(scopeID: workspace.mainEventID, entityID: UUID(),
            localFileURL: mediaFile, contentType: "image/jpeg", ownerUserID: "deleted"))
        try context.save()
        let generation = persistence.activeUserGeneration
        #expect(throws: (any Error).self) {
            try persistence.purgeLocalData(accountID: "deleted", from: library)
        }
        let verification = ModelContext(persistence.container)
        #expect(try verification.fetch(FetchDescriptor<WorkspaceRecord>()).count == 1)
        #expect(try verification.fetch(FetchDescriptor<PendingMediaTransfer>()).count == 1)
        #expect(try !verification.fetch(FetchDescriptor<PendingMutation>()).isEmpty)
        #expect(library.workspaces.first === workspace)
        #expect(persistence.activeUserGeneration == generation)

        try FileManager.default.removeItem(at: blocker)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        try Data([2]).write(to: mediaFile)
        try persistence.purgeLocalData(accountID: "deleted", from: library)
        #expect(library.workspaces.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: mediaFile.path))
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMediaTransfer>()).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "AccountDeletion-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
