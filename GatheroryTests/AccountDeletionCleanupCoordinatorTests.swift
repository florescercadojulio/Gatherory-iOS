import Foundation
import Testing
@testable import Gatherory

@MainActor
struct AccountDeletionCleanupCoordinatorTests {
    @Test("Unconfirmed deletion never cleans up automatically, including after relaunch")
    func awaitingConfirmationSurvivesRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "pending.json")
        let first = AccountDeletionCleanupCoordinator(journal: DeviceAccountDeletionCleanupJournal(fileURL: file))
        var cleanupAccounts: [String] = []
        first.removeLocalData = { cleanupAccounts.append($0) }
        try first.begin(accountID: "account-a")
        await first.retry()

        let relaunched = AccountDeletionCleanupCoordinator(journal: DeviceAccountDeletionCleanupJournal(fileURL: file))
        relaunched.removeLocalData = { accountID in
            let persisted = try DeviceAccountDeletionCleanupJournal(fileURL: file).load()
            #expect(persisted?.phase == .deviceRemovalConfirmed)
            cleanupAccounts.append(accountID)
        }
        await relaunched.retry()
        #expect(cleanupAccounts.isEmpty)
        #expect(relaunched.blocksEntry)
        #expect(relaunched.needsConfirmation)
        #expect(relaunched.record == AccountDeletionCleanupRecord(accountID: "account-a", phase: .awaitingConfirmation))

        await relaunched.confirmDeviceRemoval()
        #expect(cleanupAccounts == ["account-a"])
        #expect(!relaunched.blocksEntry)
        #expect(try DeviceAccountDeletionCleanupJournal(fileURL: file).load() == nil)
    }

    @Test("Acknowledged deletion retains its identity on cleanup failure and a new coordinator retries it")
    func cleanupFailureAndRelaunchRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "pending.json")
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        let first = AccountDeletionCleanupCoordinator(journal: journal)
        var accounts: [String] = []
        first.removeLocalData = { accountID in
            accounts.append(accountID)
            throw AccountDeletionTestFailure.cleanup
        }
        try first.begin(accountID: "account-a")
        first.confirmRemoteDeletion()
        await first.retry()
        #expect(first.lastError as? AccountDeletionTestFailure == .cleanup)
        #expect(first.blocksEntry)
        #expect(!first.isCleaning)
        #expect(try journal.load() == AccountDeletionCleanupRecord(accountID: "account-a", phase: .confirmed))

        let relaunched = AccountDeletionCleanupCoordinator(journal: DeviceAccountDeletionCleanupJournal(fileURL: file))
        relaunched.removeLocalData = { accounts.append($0) }
        await relaunched.retry()
        #expect(accounts == ["account-a", "account-a"])
        #expect(try journal.load() == nil)
        #expect(relaunched.record == nil)
        #expect(relaunched.lastError == nil)
        #expect(!relaunched.blocksEntry)
    }

    @Test("A failed remote request cancels its intent without touching local data")
    func cancelFailedRemoteRequest() async throws {
        let journal = AccountDeletionTestJournal()
        let coordinator = AccountDeletionCleanupCoordinator(journal: journal)
        var hasLocalData = true
        coordinator.removeLocalData = { _ in hasLocalData = false }
        try coordinator.begin(accountID: "account-a")
        coordinator.cancelUnconfirmedRequest()
        await coordinator.retry()
        #expect(hasLocalData)
        #expect(journal.record == nil)
        #expect(!coordinator.blocksEntry)
    }

    @Test("Cleanup waits for durable confirmation when saving the acknowledgement fails")
    func failedConfirmationWriteCannotDestroyData() async throws {
        let journal = AccountDeletionTestJournal()
        let coordinator = AccountDeletionCleanupCoordinator(journal: journal)
        var cleanupAccounts: [String] = []
        coordinator.removeLocalData = { accountID in
            #expect(journal.record?.phase == .confirmed)
            cleanupAccounts.append(accountID)
        }
        try coordinator.begin(accountID: "account-a")
        journal.failingSavePhase = .confirmed
        coordinator.confirmRemoteDeletion()
        await coordinator.retry()
        #expect(cleanupAccounts.isEmpty)
        #expect(coordinator.record?.phase == .confirmed)
        #expect(journal.record?.phase == .awaitingConfirmation)
        #expect(coordinator.lastError as? AccountDeletionTestFailure == .write)
        #expect(coordinator.blocksEntry)

        journal.failingSavePhase = nil
        await coordinator.retry()
        #expect(cleanupAccounts == ["account-a"])
        #expect(journal.record == nil)
        #expect(!coordinator.blocksEntry)
    }

    @Test("Failure to clear the journal repeats cleanup safely before releasing entry")
    func journalClearFailureRetriesIdempotentCleanup() async throws {
        let journal = AccountDeletionTestJournal()
        let coordinator = AccountDeletionCleanupCoordinator(journal: journal)
        var remainingArtifacts = Set(["account-a"])
        var cleanupCount = 0
        coordinator.removeLocalData = { accountID in
            cleanupCount += 1
            remainingArtifacts.remove(accountID)
        }
        try coordinator.begin(accountID: "account-a")
        coordinator.confirmRemoteDeletion()
        journal.failRemove = true
        await coordinator.retry()
        #expect(remainingArtifacts.isEmpty)
        #expect(coordinator.lastError as? AccountDeletionTestFailure == .remove)
        #expect(coordinator.blocksEntry)
        #expect(journal.record?.phase == .confirmed)

        journal.failRemove = false
        await coordinator.retry()
        #expect(cleanupCount == 2)
        #expect(remainingArtifacts.isEmpty)
        #expect(journal.record == nil)
        #expect(!coordinator.blocksEntry)
    }

    @Test("A stale confirmed identity cannot clean up after its journal becomes corrupt")
    func corruptReloadFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "pending.json")
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        try journal.save(AccountDeletionCleanupRecord(accountID: "account-a", phase: .confirmed))
        let coordinator = AccountDeletionCleanupCoordinator(journal: journal)
        var cleanupCount = 0
        coordinator.removeLocalData = { _ in cleanupCount += 1 }
        let corrupt = Data("unreadable pending cleanup".utf8)
        try corrupt.write(to: file, options: .atomic)

        coordinator.reload()
        await coordinator.retry()

        #expect(coordinator.journalUnreadable)
        #expect(coordinator.blocksEntry)
        #expect(coordinator.lastError != nil)
        #expect(cleanupCount == 0)
        #expect(try Data(contentsOf: file) == corrupt)
    }
}

enum AccountDeletionTestFailure: Error, Equatable {
    case load
    case write
    case remove
    case cleanup
    case remote
    case freeze
}

@MainActor
final class AccountDeletionTestJournal: AccountDeletionCleanupJournaling {
    var record: AccountDeletionCleanupRecord?
    var failLoad = false
    var failAllSaves = false
    var failingSavePhase: AccountDeletionCleanupRecord.Phase?
    var failRemove = false

    func load() throws -> AccountDeletionCleanupRecord? {
        if failLoad { throw AccountDeletionTestFailure.load }
        return record
    }

    func save(_ record: AccountDeletionCleanupRecord) throws {
        if failAllSaves || failingSavePhase == record.phase { throw AccountDeletionTestFailure.write }
        self.record = record
    }

    func remove() throws {
        if failRemove { throw AccountDeletionTestFailure.remove }
        record = nil
    }
}
