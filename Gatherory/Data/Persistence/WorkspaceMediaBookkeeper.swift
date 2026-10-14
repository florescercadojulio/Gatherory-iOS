import Foundation
import SwiftData

/// Stages file-backed media bookkeeping in the caller's context. The caller
/// owns saving, rollback, and any follow-up notifications.
@MainActor
struct WorkspaceMediaBookkeeper {
    private let context: ModelContext
    private let codec: WorkspaceArchiveCodec
    private let ownerUserID: String?

    init(context: ModelContext, codec: WorkspaceArchiveCodec, ownerUserID: String?) {
        self.context = context
        self.codec = codec
        self.ownerUserID = ownerUserID
    }

    func stagePreparation(from library: WorkspaceLibrary) throws {
        let existing = try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .filter { $0.ownerUserID == ownerUserID }
        let existingByEntity = Dictionary(
            existing.map { (($0.scopeID.uuidString + $0.entityID.uuidString), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var activeKeys = Set<String>()

        for workspace in library.workspaces {
            for attachment in workspace.mediaAttachments
            where attachment.mediaAssetID == nil {
                guard let data = attachment.imageData, !data.isEmpty else { continue }
                let key = workspace.mainEventID.uuidString + attachment.entityID.uuidString
                activeKeys.insert(key)
                if let transfer = existingByEntity[key] {
                    try data.write(to: URL(fileURLWithPath: transfer.localFilePath), options: .atomic)
                    if transfer.state == .requiresAttention {
                        transfer.state = .pending
                        transfer.nextAttemptAt = nil
                    }
                    continue
                }

                let contentType = Self.imageContentType(for: data)
                let id = UUID()
                let fileURL = try mediaOutboxURL(
                    transferID: id,
                    fileExtension: Self.fileExtension(for: contentType)
                )
                try data.write(to: fileURL, options: .atomic)
                context.insert(
                    PendingMediaTransfer(
                        id: id,
                        scopeID: workspace.mainEventID,
                        entityID: attachment.entityID,
                        localFileURL: fileURL,
                        contentType: contentType,
                        ownerUserID: ownerUserID
                    )
                )
            }
        }

        for transfer in existing
        where !activeKeys.contains(transfer.scopeID.uuidString + transfer.entityID.uuidString) {
            try? FileManager.default.removeItem(atPath: transfer.localFilePath)
            context.delete(transfer)
        }
    }

    /// Removes image bytes from legacy structured mutations before they are pushed.
    func stageSanitization() throws {
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
            .filter { $0.ownerUserID == ownerUserID && $0.operation != .delete }
        for mutation in mutations {
            let sanitized: Data?
            switch mutation.entityType {
            case .workspace:
                sanitized = try codec.decode(WorkspaceArchiveV1.self, from: mutation.payload)
                    .syncPayload(using: codec)
            case .idea:
                var record = try codec.decode(PlanningIdea.self, from: mutation.payload)
                record.imageData = nil
                sanitized = try codec.encode(record)
            case .event:
                var record = try codec.decode(TimelineItem.self, from: mutation.payload)
                record.imageData = nil
                sanitized = try codec.encode(record)
            case .moment:
                var record = try codec.decode(EventMoment.self, from: mutation.payload)
                record.imageData = Data()
                sanitized = try codec.encode(record)
            case .registryItem:
                var record = try codec.decode(RegistryItem.self, from: mutation.payload)
                record.imageData = nil
                sanitized = try codec.encode(record)
            default:
                sanitized = nil
            }
            if let sanitized, mutation.payload != sanitized {
                mutation.payload = sanitized
                mutation.state = .pending
                mutation.leaseExpiresAt = nil
                mutation.nextAttemptAt = nil
                mutation.lastFailureCode = nil
            }
        }
    }

    func pendingMediaTransfers(scopeID: UUID? = nil) throws -> [PendingMediaTransferSnapshot] {
        try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .filter {
                $0.ownerUserID == ownerUserID
                    && (scopeID == nil || $0.scopeID == scopeID)
                    && $0.state != .uploading
                    && ($0.nextAttemptAt == nil || $0.nextAttemptAt! <= .now)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                PendingMediaTransferSnapshot(
                    id: $0.id,
                    scopeID: $0.scopeID,
                    entityID: $0.entityID,
                    localFileURL: URL(fileURLWithPath: $0.localFilePath),
                    contentType: $0.contentType,
                    attemptCount: $0.attemptCount
                )
            }
    }

    func hasPendingMediaTransfers() throws -> Bool {
        try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .contains { $0.ownerUserID == ownerUserID }
    }

    func pendingMediaScopeIDs() throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .filter { $0.ownerUserID == ownerUserID }.map(\.scopeID))
    }

    func stageUploading(_ id: UUID) throws -> Bool {
        guard let transfer = try mediaTransfer(id) else { return false }
        transfer.state = .uploading
        return true
    }

    func stageCompletion(_ id: UUID) throws -> Bool {
        guard let transfer = try mediaTransfer(id) else { return false }
        try? FileManager.default.removeItem(atPath: transfer.localFilePath)
        context.delete(transfer)
        return true
    }

    func stageFailure(_ id: UUID) throws -> Bool {
        guard let transfer = try mediaTransfer(id) else { return false }
        transfer.attemptCount += 1
        transfer.state = transfer.attemptCount >= 5 ? .requiresAttention : .pending
        transfer.nextAttemptAt = transfer.state == .pending
            ? Date.now.addingTimeInterval(min(pow(2, Double(transfer.attemptCount)), 60))
            : nil
        return true
    }

    func stageFinalRetry() throws {
        for transfer in try context.fetch(FetchDescriptor<PendingMediaTransfer>())
        where transfer.ownerUserID == ownerUserID && transfer.state == .pending {
            transfer.nextAttemptAt = nil
        }
    }

    func stageRemoval(scopeID: UUID? = nil) throws {
        let transfers = try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .filter { $0.ownerUserID == ownerUserID && (scopeID == nil || $0.scopeID == scopeID) }
        for transfer in transfers {
            try? FileManager.default.removeItem(atPath: transfer.localFilePath)
            context.delete(transfer)
        }
    }

    private func mediaTransfer(_ id: UUID) throws -> PendingMediaTransfer? {
        try context.fetch(FetchDescriptor<PendingMediaTransfer>())
            .first { $0.id == id && $0.ownerUserID == ownerUserID }
    }

    private func mediaOutboxURL(transferID: UUID, fileExtension: String) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appending(path: "GatheroryMediaOutbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(transferID.uuidString).\(fileExtension)")
    }

    private static func imageContentType(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) { return "image/webp" }
        if bytes.count >= 12,
           String(bytes: bytes[4..<12], encoding: .ascii)?.contains("ftypheic") == true {
            return "image/heic"
        }
        if bytes.count >= 12,
           String(bytes: bytes[4..<12], encoding: .ascii)?.contains("ftypheif") == true {
            return "image/heif"
        }
        return "image/jpeg"
    }

    private static func fileExtension(for contentType: String) -> String {
        switch contentType {
        case "image/png": "png"
        case "image/webp": "webp"
        case "image/heic": "heic"
        case "image/heif": "heif"
        default: "jpg"
        }
    }
}
