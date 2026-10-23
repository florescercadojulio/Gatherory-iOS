import Foundation
import Testing
@testable import Gatherory

@MainActor
struct ExploreAdSessionLifecycleTests {
    @Test("Covered preview suspension is idempotent and resume opens a new owner lifecycle")
    func coveredPreviewSuspendAndResume() {
        let session = ExploreAdSession(scopeID: "test-scope")

        session.suspendForCoveredPreview()
        let suspendedGeneration = session.lifecycleGeneration
        #expect(session.isSuspended)
        #expect(suspendedGeneration == 0)
        #expect(!session.claim(slotID: "slot-1", ownerID: UUID()))

        session.suspendForCoveredPreview()
        #expect(session.lifecycleGeneration == suspendedGeneration)

        session.resumeFromCoveredPreview()
        #expect(!session.isSuspended)
        #expect(session.lifecycleGeneration == suspendedGeneration + 1)

        session.resumeFromCoveredPreview()
        #expect(session.lifecycleGeneration == suspendedGeneration + 1)
    }

    @Test("Full reset clears preview suspension")
    func resetClearsSuspension() {
        let session = ExploreAdSession(scopeID: "test-scope")
        session.suspendForCoveredPreview()

        session.reset()

        #expect(!session.isSuspended)
        #expect(session.lifecycleGeneration == 1)
    }
}
