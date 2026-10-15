import Testing
@testable import Gatherory

@MainActor
struct BlueprintSetupRecoveryTests {
    private enum Failure: Error { case unreadable }

    @Test("An unreadable draft cannot hide a pending installation")
    func pendingSurvivesDraftFailure() {
        var owners: [String] = []
        let recovery = BlueprintSetupRecovery.load(ownerID: "account-a", readDrafts: { owner in
            owners.append(owner)
            throw Failure.unreadable
        }, readPending: { owner in
            owners.append(owner)
            return true
        })
        #expect(recovery.drafts.isEmpty)
        #expect(recovery.hasPendingInstallation)
        #expect(recovery.loadFailed)
        #expect(owners == ["account-a", "account-a"])
    }

    @Test("Unreadable installation storage remains an explicit retry state")
    func pendingReadFailure() {
        var readDrafts = false
        let recovery = BlueprintSetupRecovery.load(ownerID: "account-b", readDrafts: { owner in
            #expect(owner == "account-b")
            readDrafts = true
            return []
        }, readPending: { owner in
            #expect(owner == "account-b")
            throw Failure.unreadable
        })
        #expect(readDrafts && recovery.loadFailed)
        #expect(!recovery.hasPendingInstallation)
    }

    @Test("Signed-out recovery cannot read any account's files")
    func signedOut() {
        let recovery = BlueprintSetupRecovery.load(ownerID: "", readDrafts: { _ in
            Issue.record("Signed-out recovery must not read drafts")
            return []
        }, readPending: { _ in
            Issue.record("Signed-out recovery must not read installation intents")
            return true
        })
        #expect(recovery.drafts.isEmpty && !recovery.hasPendingInstallation && !recovery.loadFailed)
    }
}
