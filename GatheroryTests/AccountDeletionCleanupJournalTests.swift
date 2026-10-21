import Foundation
import Testing
@testable import Gatherory

@MainActor
struct AccountDeletionCleanupJournalTests {
    @Test("Explicit device removal persists separately from a remote deletion acknowledgement")
    func deviceRemovalConfirmationIsDistinctAndDurable() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "pending.json")
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        try journal.save(AccountDeletionCleanupRecord(accountID: "account-a", phase: .awaitingConfirmation))
        let deviceRemoval = AccountDeletionCleanupRecord(accountID: "account-a", phase: .deviceRemovalConfirmed)
        try journal.save(deviceRemoval)
        try journal.save(deviceRemoval)
        #expect(try DeviceAccountDeletionCleanupJournal(fileURL: file).load() == deviceRemoval)
        #expect(throws: AccountDeletionCleanupJournalError.phaseRegression) {
            try journal.save(AccountDeletionCleanupRecord(accountID: "account-a", phase: .awaitingConfirmation))
        }
        #expect(try journal.load() == deviceRemoval)
    }

    @Test("Deletion cleanup survives reopening and duplicate phase writes")
    func durablePhasesAndDuplicateWrites() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "nested/pending.json")
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        #expect(try journal.load() == nil)
        try journal.remove()
        let awaiting = AccountDeletionCleanupRecord(accountID: "account-a", phase: .awaitingConfirmation)
        try journal.save(awaiting)
        try journal.save(awaiting)
        #expect(try DeviceAccountDeletionCleanupJournal(fileURL: file).load() == awaiting)

        let confirmed = AccountDeletionCleanupRecord(accountID: "account-a", phase: .confirmed)
        try DeviceAccountDeletionCleanupJournal(fileURL: file).save(confirmed)
        try journal.save(confirmed)
        #expect(try journal.load() == confirmed)
        #expect(throws: AccountDeletionCleanupJournalError.phaseRegression) {
            try journal.save(awaiting)
        }
        #expect(try journal.load() == confirmed)
        try journal.remove()
        try journal.remove()
        #expect(try DeviceAccountDeletionCleanupJournal(fileURL: file).load() == nil)
    }

    @Test("Another account cannot replace pending cleanup")
    func accountIsolation() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "pending.json")
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        let original = AccountDeletionCleanupRecord(accountID: "account-a", phase: .confirmed)
        try journal.save(original)
        let bytes = try Data(contentsOf: file)

        #expect(throws: AccountDeletionCleanupJournalError.accountMismatch) {
            try DeviceAccountDeletionCleanupJournal(fileURL: file).save(
                AccountDeletionCleanupRecord(accountID: "account-b", phase: .awaitingConfirmation)
            )
        }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try journal.load() == original)
        try journal.remove()
        let next = AccountDeletionCleanupRecord(accountID: "account-b", phase: .awaitingConfirmation)
        try journal.save(next)
        #expect(try journal.load() == next)
    }

    @Test("Invalid identities are rejected on write and on reopening")
    func validatesSavedAndDecodedIdentity() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "pending.json")
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        for accountID in ["", " \n\t", String(repeating: "a", count: 129), String(repeating: "e\u{301}", count: 65)] {
            let invalid = AccountDeletionCleanupRecord(accountID: accountID, phase: .confirmed)
            #expect(throws: AccountDeletionCleanupJournalError.invalidAccountID) { try journal.save(invalid) }
            #expect(try journal.load() == nil)
        }
        let boundary = AccountDeletionCleanupRecord(accountID: String(repeating: "a", count: 128), phase: .confirmed)
        try journal.save(boundary)
        #expect(try journal.load() == boundary)
        try JSONEncoder().encode(AccountDeletionCleanupRecord(accountID: "", phase: .confirmed))
            .write(to: file, options: .atomic)
        #expect(throws: AccountDeletionCleanupJournalError.invalidAccountID) { try journal.load() }
        #expect(throws: AccountDeletionCleanupJournalError.invalidAccountID) { try journal.save(boundary) }
    }

    @Test("Corrupt records and unsupported phases cannot be overwritten")
    func preservesCorruptJournal() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appending(path: "pending.json")
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        for bytes in [Data("not-json".utf8), Data(#"{"accountID":"account-a","phase":"future-phase"}"#.utf8)] {
            try bytes.write(to: file, options: .atomic)
            #expect(throws: DecodingError.self) { try journal.load() }
            #expect(throws: DecodingError.self) {
                try journal.save(AccountDeletionCleanupRecord(accountID: "account-a", phase: .confirmed))
            }
            #expect(try Data(contentsOf: file) == bytes)
        }
    }

    @Test("An unreadable journal location surfaces an error without replacing it")
    func unreadableLocationIsPreserved() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "pending.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let sentinel = file.appending(path: "keep.txt")
        let bytes = Data("unrelated file".utf8)
        try bytes.write(to: sentinel)
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        #expect(throws: (any Error).self) { try journal.load() }
        #expect(throws: (any Error).self) {
            try journal.save(AccountDeletionCleanupRecord(accountID: "account-a", phase: .confirmed))
        }
        #expect(try Data(contentsOf: sentinel) == bytes)
    }

    @Test("Persisted cleanup contains only its account identity and phase")
    func storesOnlyCleanupMetadata() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "pending.json")
        let journal = DeviceAccountDeletionCleanupJournal(fileURL: file)
        try journal.save(AccountDeletionCleanupRecord(accountID: "account-a", phase: .awaitingConfirmation))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
        #expect(object == ["accountID": "account-a", "phase": "awaitingConfirmation"])
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AccountDeletionJournalTests-\(UUID())")
    }
}
