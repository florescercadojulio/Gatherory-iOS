import Foundation
import Testing
@testable import Gatherory

@MainActor struct ImageSafetyTests {
    @Test("An offline block hides content locally, survives relaunch, and retries without changing shared data")
    func offlineBlock() async throws {
        let suite = "image-safety-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = SafetyTestClient()
        client.fails = true
        let store = ImageSafetyStore(defaults: defaults, client: client)
        store.configure(accountID: "account-a")
        do { try await store.block("account-b", name: "Guest") } catch {}
        #expect(store.isBlocked("account-b"))
        #expect(store.pendingBlockIDs.contains("account-b"))
        let restored = ImageSafetyStore(defaults: defaults, client: client)
        restored.configure(accountID: "account-a")
        #expect(restored.isBlocked("account-b"))
        restored.configure(accountID: "account-c")
        #expect(!restored.isBlocked("account-b"))
        restored.configure(accountID: "account-a")
        client.fails = false
        await restored.refresh()
        #expect(restored.pendingBlockIDs.isEmpty)
        #expect(restored.isBlocked("account-b"))
        #expect(client.blocked == ["account-b"])
        try await restored.unblock("account-b")
        #expect(!restored.isBlocked("account-b"))
        #expect(client.blocked.isEmpty)
    }

    @Test("Failed unblock keeps the block; account deletion removes its local safety preferences")
    func unblockFailureAndPurge() async throws {
        let suite = "image-safety-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = SafetyTestClient()
        let store = ImageSafetyStore(defaults: defaults, client: client)
        store.configure(accountID: "account-a")
        try await store.block("account-b", name: "Guest")
        client.fails = true
        do { try await store.unblock("account-b") } catch {}
        #expect(store.isBlocked("account-b"))
        store.purge(accountID: "account-a")
        #expect(store.accountID == nil)
        let restored = ImageSafetyStore(defaults: defaults, client: client)
        restored.configure(accountID: "account-a")
        #expect(restored.blockedUserIDs.isEmpty)
    }

    @Test("Self-block is ignored")
    func selfBlock() async throws {
        let suite = "image-safety-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = SafetyTestClient()
        let store = ImageSafetyStore(defaults: defaults, client: client)
        store.configure(accountID: "account-a")
        try await store.block("account-a", name: "Me")
        #expect(store.blockedUserIDs.isEmpty)
        #expect(client.blocked.isEmpty)
    }
    @Test("Hidden images are personal, persistent, and isolated across accounts")
    func accountIsolation() throws {
        let suite = "image-safety-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ImageSafetyStore(defaults: defaults)
        let moment = EventMoment(mediaAssetID: UUID(), imageData: Data([1, 2, 3]), addedBy: "Guest")
        store.configure(accountID: "account-a")
        #expect(!store.isHidden(moment))
        store.hide(moment)
        #expect(store.isHidden(moment))
        #expect(store.visibleImageData(moment.imageData, assetID: moment.mediaAssetID) == nil)
        let restored = ImageSafetyStore(defaults: defaults)
        restored.configure(accountID: "account-a")
        #expect(restored.isHidden(moment))
        store.configure(accountID: "account-b")
        #expect(!store.isHidden(moment))
        #expect(store.visibleImageData(moment.imageData, assetID: moment.mediaAssetID) == moment.imageData)
        store.configure(accountID: nil)
        #expect(store.hiddenIDs.isEmpty)
        #expect(store.moderatedIDs.isEmpty)
    }

    @Test("An offline photo can be hidden without changing shared image bytes")
    func localPhoto() throws {
        let suite = "image-safety-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ImageSafetyStore(defaults: defaults)
        let moment = EventMoment(imageData: Data([1]), addedBy: "Guest")
        store.configure(accountID: "account-a")
        store.hide(moment)
        #expect(store.isHidden(moment))
        #expect(moment.imageData == Data([1]))
        #expect(store.visibleImageData(Data([2]), assetID: UUID()) == Data([2]))
    }
}

@MainActor private final class SafetyTestClient: ImageSafetyPolicyClient {
    var fails = false
    var blocked: Set<String> = []
    func blockedPeople() async throws -> [BlockedPerson] {
        if fails { throw MediaSyncFailure.invalidResponse }
        return blocked.map { BlockedPerson(userId: $0, name: "Guest") }
    }
    func hiddenIDs() async throws -> Set<UUID> {
        if fails { throw MediaSyncFailure.invalidResponse }
        return []
    }
    func block(_ userID: String) async throws {
        if fails { throw MediaSyncFailure.invalidResponse }
        blocked.insert(userID)
    }
    func unblock(_ userID: String) async throws {
        if fails { throw MediaSyncFailure.invalidResponse }
        blocked.remove(userID)
    }
}
