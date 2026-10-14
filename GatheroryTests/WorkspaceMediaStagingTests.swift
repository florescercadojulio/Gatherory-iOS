import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct WorkspaceMediaStagingTests {
    @Test("Media queries and final retry preserve due-time, state, scope, and owner distinctions")
    func queriesAndFinalRetry() throws {
        let context = try makeContext()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scopeID = UUID()
        let ready = transfer(scopeID, url: directory.appending(path: "ready.jpg"))
        let delayed = transfer(UUID(), url: directory.appending(path: "delayed.jpg"))
        let uploading = transfer(UUID(), url: directory.appending(path: "uploading.jpg"))
        let attention = transfer(scopeID, url: directory.appending(path: "attention.jpg"))
        let other = transfer(scopeID, url: directory.appending(path: "other.jpg"), owner: "other")
        ready.createdAt = Date(timeIntervalSinceReferenceDate: 20)
        attention.createdAt = Date(timeIntervalSinceReferenceDate: 10)
        delayed.nextAttemptAt = .distantFuture
        uploading.state = .uploading
        uploading.nextAttemptAt = .distantFuture
        attention.state = .requiresAttention
        other.nextAttemptAt = .distantFuture
        for row in [ready, delayed, uploading, attention, other] { context.insert(row) }
        try context.save()
        let helper = bookkeeper(context)
        #expect(try helper.pendingMediaTransfers().map(\.id) == [attention.id, ready.id])
        #expect(try helper.pendingMediaTransfers(scopeID: delayed.scopeID).isEmpty)
        #expect(try helper.hasPendingMediaTransfers())
        #expect(try helper.pendingMediaScopeIDs() == [scopeID, delayed.scopeID, uploading.scopeID])

        attention.nextAttemptAt = .distantFuture
        try context.save()
        try helper.stageFinalRetry()
        #expect(delayed.nextAttemptAt == nil)
        #expect(uploading.nextAttemptAt == .distantFuture)
        #expect(attention.nextAttemptAt == .distantFuture)
        #expect(other.nextAttemptAt == .distantFuture)
        #expect(try rows(ModelContext(context.container)).first { $0.id == delayed.id }?.nextAttemptAt == .distantFuture)
    }

    @Test("Preparation keeps file writes before row commits, even when a later write fails")
    func preparationFailurePreservesOrdering() throws {
        let context = try makeContext()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = workspace("First", image: Data([1, 2]))
        let second = workspace("Second", image: Data([3, 4]))
        let firstURL = directory.appending(path: "first.jpg")
        try Data([0]).write(to: firstURL)
        let firstTransfer = transfer(first.mainEventID, url: firstURL)
        firstTransfer.state = .requiresAttention
        firstTransfer.attemptCount = 5
        firstTransfer.nextAttemptAt = .distantFuture
        let secondTransfer = transfer(second.mainEventID,
            url: directory.appending(path: "missing/second.jpg"))
        context.insert(firstTransfer)
        context.insert(secondTransfer)
        try context.save()

        #expect(throws: (any Error).self) {
            try bookkeeper(context).stagePreparation(from: WorkspaceLibrary(workspaces: [first, second]))
        }

        #expect(try Data(contentsOf: firstURL) == Data([1, 2]))
        #expect(firstTransfer.state == .pending)
        #expect(firstTransfer.attemptCount == 5)
        #expect(firstTransfer.nextAttemptAt == nil)
        let durable = try #require(rows(ModelContext(context.container)).first { $0.id == firstTransfer.id })
        #expect(durable.state == .requiresAttention)
        #expect(durable.nextAttemptAt == .distantFuture)
        context.rollback()
        #expect(firstTransfer.state == .requiresAttention)
        // SwiftData rollback has never rolled back file-system writes.
        #expect(try Data(contentsOf: firstURL) == Data([1, 2]))
    }

    @Test("Scope removal stages only this account's rows but removes files immediately")
    func removalDoesNotCommit() throws {
        let context = try makeContext()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let scopeID = UUID()
        let removed = transfer(scopeID, url: directory.appending(path: "removed.jpg"))
        let otherScope = transfer(UUID(), url: directory.appending(path: "scope.jpg"))
        let otherOwner = transfer(scopeID, url: directory.appending(path: "owner.jpg"), owner: "other")
        for row in [removed, otherScope, otherOwner] {
            try Data([1]).write(to: URL(fileURLWithPath: row.localFilePath))
            context.insert(row)
        }
        try context.save()

        try bookkeeper(context).stageRemoval(scopeID: scopeID)

        #expect(context.deletedModelsArray.contains { $0 === removed })
        #expect(!FileManager.default.fileExists(atPath: removed.localFilePath))
        #expect(FileManager.default.fileExists(atPath: otherScope.localFilePath))
        #expect(FileManager.default.fileExists(atPath: otherOwner.localFilePath))
        #expect(try rows(ModelContext(context.container)).count == 3)
        context.rollback()
        #expect(try rows(context).count == 3)
        #expect(!FileManager.default.fileExists(atPath: removed.localFilePath))

        // Account-wide purge also tolerates a file that is already missing.
        try bookkeeper(context).stageRemoval()
        #expect(try rows(ModelContext(context.container)).count == 3)
        try context.save()
        #expect(try rows(ModelContext(context.container)).map(\.id) == [otherOwner.id])
        #expect(FileManager.default.fileExists(atPath: otherOwner.localFilePath))
    }

    @Test("Media state transitions return whether the controller should save, without saving themselves")
    func transitionsRemainStaged() throws {
        let context = try makeContext()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let row = transfer(UUID(), url: directory.appending(path: "media.jpg"))
        context.insert(row)
        try context.save()
        let helper = bookkeeper(context)
        let missing = UUID()
        #expect(try !helper.stageUploading(missing))
        #expect(try !helper.stageFailure(missing))
        #expect(try !helper.stageCompletion(missing))
        #expect(!context.hasChanges)
        #expect(try helper.stageUploading(row.id))
        #expect(row.state == .uploading)
        #expect(try rows(ModelContext(context.container)).first?.state == .pending)
        #expect(try helper.stageFailure(row.id))
        #expect(row.attemptCount == 1)
        #expect(row.nextAttemptAt != nil)
        try helper.stageFinalRetry()
        #expect(row.nextAttemptAt == nil)
        #expect(try rows(ModelContext(context.container)).first?.attemptCount == 0)
        context.rollback()
        #expect(row.attemptCount == 0)
        #expect(try helper.stageCompletion(row.id))
        #expect(try rows(ModelContext(context.container)).count == 1)
        try context.save()
        #expect(try rows(ModelContext(context.container)).isEmpty)
    }

    @Test("Legacy sanitization stages metadata and retry changes without committing")
    func sanitizationDoesNotCommit() throws {
        let context = try makeContext()
        let archive = WorkspaceArchiveV1(workspace: workspace("Legacy", image: Data([1, 2, 3])))
        let original = try WorkspaceArchiveCodec().encode(archive)
        let mutation = PendingMutation(scopeID: archive.mainEventID, entityType: .workspace,
            entityID: archive.mainEventID, operation: .create, payload: original, ownerUserID: "owner")
        mutation.state = .requiresAttention
        mutation.attemptCount = 5
        context.insert(mutation)
        try context.save()

        try bookkeeper(context).stageSanitization()

        #expect(mutation.payload != original)
        #expect(mutation.state == .pending)
        #expect(mutation.attemptCount == 5)
        let reader = ModelContext(context.container)
        #expect(try reader.fetch(FetchDescriptor<PendingMutation>()).first?.payload == original)
        context.rollback()
        #expect(mutation.payload == original)
        #expect(mutation.state == .requiresAttention)
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(schema: OfflineSyncSchema.schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: OfflineSyncSchema.schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MediaStaging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func workspace(_ title: String, image: Data) -> PlanningWorkspace {
        PlanningWorkspace.newWorkspace(title: title, startsAt: .now, eventLocation: nil, imageData: image)
    }

    private func transfer(_ scopeID: UUID, url: URL, owner: String = "owner") -> PendingMediaTransfer {
        PendingMediaTransfer(scopeID: scopeID, entityID: scopeID, localFileURL: url,
            contentType: "image/jpeg", ownerUserID: owner)
    }

    private func bookkeeper(_ context: ModelContext) -> WorkspaceMediaBookkeeper {
        WorkspaceMediaBookkeeper(context: context, codec: WorkspaceArchiveCodec(), ownerUserID: "owner")
    }

    private func rows(_ context: ModelContext) throws -> [PendingMediaTransfer] {
        try context.fetch(FetchDescriptor<PendingMediaTransfer>())
    }
}
