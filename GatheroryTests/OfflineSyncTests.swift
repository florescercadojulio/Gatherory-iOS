import Foundation
import Testing
@testable import Gatherory

struct OfflineSyncTests {
    @Test("Retry delay grows exponentially and respects its cap")
    func retryBackoff() {
        let origin = Date(timeIntervalSinceReferenceDate: 1_000)
        let policy = SyncRetryPolicy(initialDelay: 5, maximumDelay: 20)

        #expect(policy.nextAttemptDate(after: 1, from: origin) == origin.addingTimeInterval(5))
        #expect(policy.nextAttemptDate(after: 2, from: origin) == origin.addingTimeInterval(10))
        #expect(policy.nextAttemptDate(after: 3, from: origin) == origin.addingTimeInterval(20))
        #expect(policy.nextAttemptDate(after: 8, from: origin) == origin.addingTimeInterval(20))
    }

    @Test("Encoded drafts preserve the stable mutation identity")
    func mutationDraftEncoding() throws {
        struct Payload: Codable, Sendable {
            let title: String
        }

        let mutationID = UUID()
        let workspaceID = UUID()
        let ideaID = UUID()
        let draft = try SyncMutationDraft(
            id: mutationID,
            scopeID: workspaceID,
            entityType: .idea,
            entityID: ideaID,
            operation: .update,
            payload: Payload(title: "Garden ceremony"),
            baseVersion: 4
        )
        let decoded = try JSONDecoder().decode(Payload.self, from: draft.payload)

        #expect(draft.id == mutationID)
        #expect(draft.scopeID == workspaceID)
        #expect(draft.entityID == ideaID)
        #expect(draft.baseVersion == 4)
        #expect(decoded.title == "Garden ceremony")
    }
}
