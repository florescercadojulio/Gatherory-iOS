import Foundation
import Observation

/// Local cleanup only. This coordinator never calls the account deletion API.
@Observable @MainActor
final class AccountDeletionCleanupCoordinator {
    private(set) var record: AccountDeletionCleanupRecord?
    private(set) var lastError: (any Error)?
    private(set) var isCleaning = false
    private(set) var journalUnreadable = false
    @ObservationIgnored private let journal: any AccountDeletionCleanupJournaling
    @ObservationIgnored var removeLocalData: ((String) async throws -> Void)?

    var blocksEntry: Bool { record != nil || journalUnreadable || isCleaning }
    var needsConfirmation: Bool { record?.phase == .awaitingConfirmation }

    init(journal: any AccountDeletionCleanupJournaling) {
        self.journal = journal
        reload()
    }

    func reload() {
        guard !isCleaning else { return }
        do {
            record = try journal.load()
            journalUnreadable = false
            lastError = nil
        } catch {
            journalUnreadable = true
            lastError = error
        }
    }

    /// Write before the remote request. An interrupted request never becomes
    /// permission to delete local records automatically on the next launch.
    func begin(accountID: String) throws {
        guard !blocksEntry else { throw AuthenticationFailure.serviceUnavailable }
        let pending = AccountDeletionCleanupRecord(accountID: accountID, phase: .awaitingConfirmation)
        try journal.save(pending)
        record = pending
        lastError = nil
    }

    /// Called only when the remote endpoint has acknowledged permanent deletion.
    /// Keep in-memory confirmation even if the disk update fails; the earlier
    /// durable intent still protects the account boundary on the next launch.
    func confirmRemoteDeletion() {
        guard let record else { return }
        let confirmed = AccountDeletionCleanupRecord(accountID: record.accountID, phase: .confirmed)
        self.record = confirmed
        do { try journal.save(confirmed); lastError = nil }
        catch { lastError = error }
    }

    func cancelUnconfirmedRequest() {
        guard record?.phase == .awaitingConfirmation else { return }
        do { try journal.remove(); record = nil; lastError = nil }
        catch { lastError = error }
    }

    /// Explicit device-only removal resolves the rare crash window where the
    /// request was sent but its response could not be recorded. No remote call.
    func confirmDeviceRemoval() async {
        guard needsConfirmation, let record else { return }
        self.record = AccountDeletionCleanupRecord(accountID: record.accountID, phase: .deviceRemovalConfirmed)
        await retry()
    }

    func retry() async {
        guard !isCleaning, let record, record.phase != .awaitingConfirmation else { return }
        guard let removeLocalData else { lastError = AuthenticationFailure.serviceUnavailable; return }
        isCleaning = true
        defer { isCleaning = false }
        do {
            // Persist confirmation before starting/remaking any destructive step.
            try journal.save(record)
            try await removeLocalData(record.accountID)
            try journal.remove()
            self.record = nil
            lastError = nil
        } catch { lastError = error }
    }
}

/// Fixtures use an isolated journal; the live bootstrap explicitly installs
/// the protected on-disk journal for relaunch recovery.
@MainActor final class MemoryAccountDeletionCleanupJournal: AccountDeletionCleanupJournaling {
    private var record: AccountDeletionCleanupRecord?
    func load() -> AccountDeletionCleanupRecord? { record }
    func save(_ record: AccountDeletionCleanupRecord) { self.record = record }
    func remove() { record = nil }
}
