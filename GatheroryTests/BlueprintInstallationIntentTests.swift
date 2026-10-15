import Foundation
import Testing
@testable import Gatherory

struct BlueprintInstallationIntentTests {
    @Test("An install retry reuses the durable account-scoped request and exact body")
    func prepareKeepsRequestStableAcrossStoreInstances() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let requestID = UUID()
        let body = Data(#"{"requestId":"stable"}"#.utf8)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try BlueprintInstallationIntentStore(directoryURL: directory).prepare(
            ownerUserID: "account-a",
            requestID: requestID,
            requestBody: body,
            createdAt: timestamp
        )
        let restored = try BlueprintInstallationIntentStore(directoryURL: directory).pending(ownerUserID: "account-a")

        #expect(restored.count == 1)
        #expect(restored.first?.requestID == first.requestID)
        #expect(restored.first?.ownerUserID == first.ownerUserID)
        #expect(restored.first?.requestBody == body)
        #expect(restored.first?.createdAt == timestamp)
    }

    @Test("Install intents stay isolated across account changes and clear only for their owner")
    func accountIsolationAndCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintInstallationIntentStore(directoryURL: directory)
        let requestID = UUID()
        try store.prepare(ownerUserID: "account-a", requestID: requestID, requestBody: Data([1]))
        try store.prepare(ownerUserID: "account-b", requestID: requestID, requestBody: Data([2]))

        #expect(try store.pending(ownerUserID: "account-a").map(\.requestBody) == [Data([1])])
        #expect(try store.pending(ownerUserID: "account-b").map(\.requestBody) == [Data([2])])
        try store.complete(ownerUserID: "account-a", requestID: requestID)
        #expect(try store.pending(ownerUserID: "account-a").isEmpty)
        #expect(try store.pending(ownerUserID: "account-b").count == 1)
    }

    @Test("A request UUID cannot be reused for changed installation content")
    func rejectsChangedBodyForSameRequestID() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BlueprintInstallationIntentStore(directoryURL: directory)
        let requestID = UUID()
        try store.prepare(ownerUserID: "account-a", requestID: requestID, requestBody: Data([1]))

        #expect(throws: BlueprintInstallationIntentFailure.requestIDAlreadyUsed) {
            try store.prepare(ownerUserID: "account-a", requestID: requestID, requestBody: Data([2]))
        }
    }
}
