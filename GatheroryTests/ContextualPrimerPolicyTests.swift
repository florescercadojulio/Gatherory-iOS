import Foundation
import Testing
@testable import Gatherory

struct ContextualPrimerPolicyTests {
    @Test("Tab education waits for onboarding and its own first active tab")
    func firstActiveTab() {
        #expect(!ContextualPrimerPolicy.shouldPresent(hasSeenPrimer: false, isTabActive: true,
            accountState: .needsOnboarding))
        #expect(!ContextualPrimerPolicy.shouldPresent(hasSeenPrimer: false, isTabActive: false,
            accountState: .complete))
        #expect(ContextualPrimerPolicy.shouldPresent(hasSeenPrimer: false, isTabActive: true,
            accountState: .complete))
        #expect(!ContextualPrimerPolicy.shouldPresent(hasSeenPrimer: true, isTabActive: true,
            accountState: .complete))
    }

    @Test("A relaunch preserves only the primer actually completed by that account")
    func persistedDismissal() throws {
        let suite = "ContextualPrimerRecovery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        ContextualPrimerStore(defaults: defaults).markSeen(.search, accountID: "a")
        let restored = ContextualPrimerStore(defaults: defaults)
        #expect(restored.hasSeen(.search, accountID: "a"))
        #expect(!restored.hasSeen(.decide, accountID: "a"))
        #expect(!restored.hasSeen(.search, accountID: "b"))
    }

    @Test("Primer dismissal is isolated by account and primer")
    func dismissalIsAccountScoped() {
        let suite = "ContextualPrimerStore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ContextualPrimerStore(defaults: defaults)

        store.markSeen(.search, accountID: "account-a")
        #expect(store.hasSeen(.search, accountID: "account-a"))
        #expect(!store.hasSeen(.search, accountID: "account-b"))
        #expect(!store.hasSeen(.decide, accountID: "account-a"))
    }

    @Test("Resetting primers for replay preserves other accounts")
    func replayResetIsAccountScoped() {
        let suite = "ContextualPrimerReplayStore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ContextualPrimerStore(defaults: defaults)

        store.markSeen(.decide, accountID: "account-a")
        store.markSeen(.search, accountID: "account-a")
        store.markSeen(.search, accountID: "account-b")
        store.reset(accountID: "account-a")

        #expect(!store.hasSeen(.decide, accountID: "account-a"))
        #expect(!store.hasSeen(.search, accountID: "account-a"))
        #expect(store.hasSeen(.search, accountID: "account-b"))
    }
}
