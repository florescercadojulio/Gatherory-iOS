import Foundation
import SwiftData
import Testing
@testable import Gatherory

@MainActor
struct WorkspaceMediaBookkeepingTests {
    @Test("New media keeps the existing MIME sniffing and filename extensions",
          arguments: ["png", "webp", "heic", "heif", "jpeg"])
    func contentTypeAndFileExtension(format: String) throws {
        let bytes: Data
        switch format {
        case "png": bytes = Data([0x89, 0x50, 0x4E, 0x47])
        case "webp": bytes = Data([0x52, 0x49, 0x46, 0x46])
        case "heic": bytes = Data([0, 0, 0, 24]) + Data("ftypheic".utf8)
        case "heif": bytes = Data([0, 0, 0, 24]) + Data("ftypheif".utf8)
        default: bytes = Data([1, 2, 3])
        }
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false)
        library.add(workspace("Format", bytes: bytes))
        try persistence.prepareMediaTransfers(from: library)
        let transfer = try #require(persistence.pendingMediaTransfers().first)
        defer { cleanup(persistence, [transfer]) }
        #expect(transfer.contentType == "image/\(format)")
        #expect(transfer.localFileURL.pathExtension == (format == "jpeg" ? "jpg" : format))
        #expect(transfer.localFileURL.deletingPathExtension().lastPathComponent == transfer.id.uuidString)
        #expect(try Data(contentsOf: transfer.localFileURL) == bytes)
    }

    @Test("Preparation reuses a transfer and file, replacing its bytes, then removes stale and linked media")
    func preparationReusesAndPrunesTransfers() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "media-owner")
        let first = workspace("First", bytes: Data([1, 2, 3]))
        let stale = workspace("Stale", bytes: Data([4, 5]))
        library.add(first)
        library.add(stale)
        try persistence.prepareMediaTransfers(from: library)
        let original = try #require(persistence.pendingMediaTransfers().first { $0.scopeID == first.mainEventID })
        let staleTransfer = try #require(persistence.pendingMediaTransfers().first { $0.scopeID == stale.mainEventID })
        defer { cleanup(persistence, [original, staleTransfer]) }
        let originalPath = original.localFileURL

        first.mainEventImageData = Data([9, 8, 7, 6])
        first.mainEventMediaAssetID = nil
        library.remove(workspaceID: stale.mainEventID)
        try persistence.prepareMediaTransfers(from: library)
        let refreshed = try #require(persistence.pendingMediaTransfers().first { $0.scopeID == first.mainEventID })
        #expect(refreshed.id == original.id)
        #expect(refreshed.localFileURL == originalPath)
        #expect(try Data(contentsOf: originalPath) == Data([9, 8, 7, 6]))
        #expect(try persistence.pendingMediaTransfers().allSatisfy { $0.id != staleTransfer.id })
        #expect(!FileManager.default.fileExists(atPath: staleTransfer.localFileURL.path))

        first.mainEventMediaAssetID = UUID()
        try persistence.prepareMediaTransfers(from: library)
        #expect(try persistence.pendingMediaTransfers().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: originalPath.path))
    }

    @Test("Media transfer queries and state changes stay isolated by account and persist independently")
    func accountIsolationAndDurableTransitions() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "one")
        let event = workspace("Account media", bytes: Data([1, 2]))
        library.add(event)
        try persistence.prepareMediaTransfers(from: library)
        let transfer = try #require(persistence.pendingMediaTransfers().first)
        defer { cleanup(persistence, [transfer]) }
        let id = transfer.id

        try persistence.markMediaTransferUploading(id)
        let marked = try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMediaTransfer>())
        #expect(try #require(marked.first { $0.id == id }).state == .uploading)
        persistence.activate(userID: "two", in: library)
        #expect(try persistence.pendingMediaTransfers().isEmpty)
        try persistence.failMediaTransfer(id)
        try persistence.completeMediaTransfer(id)
        #expect(try !persistence.hasPendingMediaTransfers())
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == id }?.attemptCount == 0)
        persistence.activate(userID: "one", in: library)
        #expect(try persistence.hasPendingMediaTransfers())
        try persistence.failMediaTransfer(id)
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == id }?.attemptCount == 1)
        try persistence.completeMediaTransfer(id)
        #expect(try ModelContext(persistence.container).fetch(FetchDescriptor<PendingMediaTransfer>()).allSatisfy { $0.id != id })
    }

    @Test("Media failures back off exponentially and require attention on the fifth attempt")
    func failureBackoffAndAttention() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "retry")
        let event = workspace("Retry", bytes: Data([3, 4]))
        library.add(event)
        try persistence.prepareMediaTransfers(from: library)
        let transfer = try #require(persistence.pendingMediaTransfers().first)
        defer { cleanup(persistence, [transfer]) }
        let id = transfer.id
        for (attempt, delay) in [2.0, 4, 8, 16].enumerated() {
            let failedAt = Date.now
            try persistence.failMediaTransfer(id)
            let saved = try #require(ModelContext(persistence.container).fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == id })
            #expect(saved.attemptCount == attempt + 1)
            #expect(saved.state == .pending)
            #expect(abs(try #require(saved.nextAttemptAt).timeIntervalSince(failedAt.addingTimeInterval(delay))) < 1)
        }
        try persistence.failMediaTransfer(id)
        let fifth = try #require(ModelContext(persistence.container).fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == id })
        #expect(fifth.attemptCount == 5)
        #expect(fifth.state == .requiresAttention)
        #expect(fifth.nextAttemptAt == nil)
    }

    @Test("Preparing again resets only the matching attention transfer")
    func preparationResetsAttentionOnlyForPendingMedia() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        let library = persistence.restoreLibrary(seedData: false, ownerUserID: "retry-reset")
        let event = workspace("Retry reset", bytes: Data([5, 6]))
        library.add(event)
        try persistence.prepareMediaTransfers(from: library)
        let transfer = try #require(persistence.pendingMediaTransfers().first)
        defer { cleanup(persistence, [transfer]) }
        for _ in 0..<5 { try persistence.failMediaTransfer(transfer.id) }
        let reader = ModelContext(persistence.container)
        let saved = try #require(reader.fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == transfer.id })
        saved.nextAttemptAt = .now.addingTimeInterval(120)
        try reader.save()
        try persistence.prepareMediaTransfers(from: library)
        let updated = try #require(ModelContext(persistence.container).fetch(FetchDescriptor<PendingMediaTransfer>()).first { $0.id == transfer.id })
        #expect(updated.state == .pending)
        #expect(updated.attemptCount == 5)
        #expect(updated.nextAttemptAt == nil)
    }

    @Test("Legacy sanitization preserves identity and attempt count while clearing retry scheduling")
    func legacyPayloadSanitization() throws {
        let persistence = try WorkspacePersistenceController(isStoredInMemoryOnly: true)
        _ = persistence.restoreLibrary(seedData: false, ownerUserID: "legacy")
        let source = workspace("Legacy", bytes: Data([7, 8, 9]))
        let archive = try WorkspaceArchiveCodec().encode(WorkspaceArchiveV1(workspace: source))
        let keep = PendingMutation(scopeID: source.mainEventID, entityType: .workspace, entityID: source.mainEventID,
            operation: .update, payload: archive, ownerUserID: "legacy")
        keep.attemptCount = 3
        keep.state = .requiresAttention
        keep.leaseExpiresAt = .distantFuture
        keep.lastFailureCode = "LEGACY_PAYLOAD"
        keep.nextAttemptAt = .now.addingTimeInterval(60)
        let deletion = PendingMutation(scopeID: source.mainEventID, entityType: .workspace, entityID: UUID(),
            operation: .delete, payload: archive, ownerUserID: "legacy")
        let other = PendingMutation(scopeID: source.mainEventID, entityType: .workspace, entityID: UUID(),
            operation: .update, payload: archive, ownerUserID: "elsewhere")
        let context = ModelContext(persistence.container)
        context.insert(keep)
        context.insert(deletion)
        context.insert(other)
        try context.save()
        try persistence.sanitizePendingMediaMutations()
        let reader = ModelContext(persistence.container)
        let saved = try reader.fetch(FetchDescriptor<PendingMutation>())
        let sanitized = try #require(saved.first { $0.id == keep.id })
        let decoded = try WorkspaceArchiveCodec().decode(WorkspaceArchiveV1.self, from: sanitized.payload)
        #expect(decoded.mainEventImageData == nil)
        #expect(sanitized.id == keep.id)
        #expect(sanitized.attemptCount == 3)
        #expect(sanitized.state == .pending)
        #expect(sanitized.nextAttemptAt == nil)
        #expect(sanitized.leaseExpiresAt == nil)
        #expect(sanitized.lastFailureCode == nil)
        #expect(try #require(saved.first { $0.id == deletion.id }).payload == archive)
        #expect(try #require(saved.first { $0.id == other.id }).payload == archive)
    }

    private func workspace(_ title: String, bytes: Data) -> PlanningWorkspace {
        PlanningWorkspace.newWorkspace(title: title, startsAt: .now, eventLocation: nil, imageData: bytes)
    }

    private func cleanup(_ persistence: WorkspacePersistenceController, _ transfers: [PendingMediaTransferSnapshot]) {
        for transfer in transfers {
            try? persistence.completeMediaTransfer(transfer.id)
            try? FileManager.default.removeItem(at: transfer.localFileURL)
        }
    }
}
