import Foundation

/// Local cleanup intent only. This record never contains credentials or a
/// request body and cannot authorize another remote deletion request.
nonisolated struct AccountDeletionCleanupRecord: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Equatable, Sendable {
        case awaitingConfirmation
        case confirmed
        case deviceRemovalConfirmed
    }

    let accountID: String
    let phase: Phase

    fileprivate func validate() throws {
        guard !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              accountID.unicodeScalars.count <= 128 else {
            throw AccountDeletionCleanupJournalError.invalidAccountID
        }
    }
}

enum AccountDeletionCleanupJournalError: Error, Equatable {
    case invalidAccountID
    case accountMismatch
    case phaseRegression
}

@MainActor protocol AccountDeletionCleanupJournaling {
    func load() throws -> AccountDeletionCleanupRecord?
    func save(_ record: AccountDeletionCleanupRecord) throws
    func remove() throws
}

/// A single pending identity keeps cleanup isolated from later sign-ins. A
/// damaged or inaccessible journal must be surfaced instead of replaced.
@MainActor struct DeviceAccountDeletionCleanupJournal: AccountDeletionCleanupJournaling {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "AccountDeletionCleanup/pending.json")
    }

    func load() throws -> AccountDeletionCleanupRecord? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let record = try JSONDecoder().decode(AccountDeletionCleanupRecord.self, from: data)
        try record.validate()
        return record
    }

    func save(_ record: AccountDeletionCleanupRecord) throws {
        try record.validate()
        if let existing = try load() {
            guard existing.accountID == record.accountID else {
                throw AccountDeletionCleanupJournalError.accountMismatch
            }
            guard existing.phase == .awaitingConfirmation || record.phase != .awaitingConfirmation else {
                throw AccountDeletionCleanupJournalError.phaseRegression
            }
            guard existing.phase != .confirmed || record.phase == .confirmed else {
                throw AccountDeletionCleanupJournalError.phaseRegression
            }
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(record).write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUnlessOpen]
        )
    }

    func remove() throws {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            // Cleanup can safely retry after the record was already removed.
        }
    }
}
