import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct CoreGatheringRecoveryTests {
    @Test("An interrupted media upload becomes eligible again on the next preparation pass")
    func interruptedMediaUploadIsRecovered() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "media-recovery-owner")
        let workspace = PlanningWorkspace.newWorkspace(
            title: "Media recovery",
            startsAt: .now,
            eventLocation: nil,
            imageData: Data([0xFF, 0xD8, 0xFF, 0x01])
        )
        library.add(workspace)
        try persistence.saveChanges(in: library)

        try persistence.prepareMediaTransfers(from: library)
        let staged = try #require(persistence.pendingMediaTransfers().first)
        defer { try? persistence.completeMediaTransfer(staged.id) }
        try persistence.markMediaTransferUploading(staged.id)

        // Restore a fresh account graph, as startup does after the process stops
        // before it can record upload completion or failure.
        let restoredLibrary = persistence.restoreLibrary(seedData: false, ownerUserID: "media-recovery-owner")
        #expect(restoredLibrary.workspaces.first?.mainEventID == workspace.mainEventID)
        try persistence.prepareMediaTransfers(from: restoredLibrary)

        let recovered = try #require(persistence.pendingMediaTransfers().first)
        #expect(recovered.id == staged.id)
        #expect(recovered.scopeID == workspace.mainEventID)
    }

    @Test("Recovering one account's upload preserves its retry identity and leaves another account untouched")
    func interruptedMediaRecoveryIsAccountScopedAndPreservesRetryCount() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "recovery-account-a")
        let eventA = PlanningWorkspace.newWorkspace(
            title: "Account A media",
            startsAt: .now,
            eventLocation: nil,
            imageData: Data([0xFF, 0xD8, 0xFF, 0x0A])
        )
        library.add(eventA)
        try persistence.saveChanges(in: library)
        try persistence.prepareMediaTransfers(from: library)
        let transferA = try #require(persistence.pendingMediaTransfers().first)

        persistence.activate(userID: "recovery-account-b", in: library)
        let eventB = PlanningWorkspace.newWorkspace(
            title: "Account B media",
            startsAt: .now,
            eventLocation: nil,
            imageData: Data([0xFF, 0xD8, 0xFF, 0x0B])
        )
        library.add(eventB)
        try persistence.saveChanges(in: library)
        try persistence.prepareMediaTransfers(from: library)
        let transferB = try #require(persistence.pendingMediaTransfers().first)
        try persistence.markMediaTransferUploading(transferB.id)
        let context = ModelContext(persistence.container)
        let storedB = try #require(context.fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == transferB.id })
        storedB.attemptCount = 4
        try context.save()

        persistence.activate(userID: "recovery-account-a", in: library)
        try persistence.markMediaTransferUploading(transferA.id)
        let storedA = try #require(context.fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == transferA.id })
        storedA.attemptCount = 2
        try context.save()
        defer {
            try? FileManager.default.removeItem(at: transferA.localFileURL)
            try? FileManager.default.removeItem(at: transferB.localFileURL)
        }

        // Re-entering account A restores its graph and reconciles only A's
        // interrupted upload. B's durable row must remain untouched.
        persistence.activate(userID: nil, in: library)
        persistence.activate(userID: "recovery-account-a", in: library)

        let retriedA = try #require(persistence.pendingMediaTransfers().first)
        #expect(retriedA.id == transferA.id)
        #expect(retriedA.attemptCount == 2)

        let unchangedB = try #require(context.fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == transferB.id })
        #expect(unchangedB.ownerUserID == "recovery-account-b")
        #expect(unchangedB.state == .uploading)
        #expect(unchangedB.attemptCount == 4)
    }
}
