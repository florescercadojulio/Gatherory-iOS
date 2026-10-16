import Foundation
import Testing
@testable import Gatherory

struct AlbumViewerStateTests {
    @Test("Opening a stale photo falls back to the first available photo")
    func staleInitialSelection() {
        let photos = [photo("A"), photo("B")]
        let state = AlbumViewerState(moments: photos, initialMomentID: UUID())
        #expect(state.selectedMomentID == photos[0].id)
        #expect(AlbumViewerState(moments: [], initialMomentID: UUID()).selectedMoment == nil)
    }

    @Test("Removing the displayed photo keeps the viewer at its nearest remaining position")
    func nearestRemainingPhoto() {
        let photos = [photo("A"), photo("B"), photo("C")]
        var state = AlbumViewerState(moments: photos, initialMomentID: photos[1].id)
        state.remove(id: photos[1].id)
        #expect(state.selectedMomentID == photos[2].id)
        state.remove(id: photos[2].id)
        #expect(state.selectedMomentID == photos[0].id)
        state.remove(id: photos[0].id)
        #expect(state.selectedMomentID == nil)
        #expect(state.moments.isEmpty)
    }

    @Test("Removing another photo preserves the displayed photo")
    func removalPreservesOtherSelection() {
        let photos = [photo("A"), photo("B"), photo("C")]
        var state = AlbumViewerState(moments: photos, initialMomentID: photos[2].id)
        state.remove(id: photos[0].id)
        #expect(state.selectedMomentID == photos[2].id)
        #expect(state.selectedIndex == 1)
    }

    @Test("Live reordering and additions preserve the current photo and refresh its metadata")
    func liveRefreshPreservesIdentity() {
        let photos = [photo("A"), photo("B")]
        var updated = photos[1]
        updated.addedBy = "Updated contributor"
        var state = AlbumViewerState(moments: photos, initialMomentID: photos[1].id)
        state.reconcile([photo("New"), updated, photos[0]])
        #expect(state.selectedMomentID == updated.id)
        #expect(state.selectedMoment?.addedBy == "Updated contributor")
    }

    @Test("A deletion confirmation remains bound to its original photo when paging")
    func confirmationKeepsOriginalTarget() {
        let photos = [photo("A"), photo("B")]
        var state = AlbumViewerState(moments: photos, initialMomentID: photos[0].id)
        state.requestDeletion(id: photos[0].id)
        state.move(by: 1)
        #expect(state.takeDeletionCandidate()?.id == photos[0].id)
        #expect(state.selectedMomentID == photos[1].id)
        #expect(state.deleteCandidateID == nil)
    }

    @Test("Consuming a deletion clears pending intent before a failed or denied delete")
    func failedDeletionCanRetry() {
        let item = photo("A")
        var state = AlbumViewerState(moments: [item], initialMomentID: item.id)
        state.requestDeletion(id: item.id)
        #expect(state.takeDeletionCandidate()?.id == item.id)
        // Simulate a rejected delete: the caller leaves the photo in place.
        #expect(state.deleteCandidateID == nil)
        #expect(state.moments == [item])
        #expect(state.takeDeletionCandidate() == nil)
        state.requestDeletion(id: item.id)
        #expect(state.takeDeletionCandidate()?.id == item.id)
    }

    @Test("Remote removal invalidates pending deletion and selects the nearest available photo")
    func remoteRemovalClearsConfirmation() {
        let photos = [photo("A"), photo("B"), photo("C")]
        var state = AlbumViewerState(moments: photos, initialMomentID: photos[1].id)
        state.requestDeletion(id: photos[1].id)
        state.reconcile([photos[0], photos[2]])
        #expect(state.deleteCandidateID == nil)
        #expect(state.takeDeletionCandidate() == nil)
        #expect(state.selectedMomentID == photos[2].id)
        state.reconcile([])
        #expect(state.selectedMomentID == nil)
    }

    @Test("Canceling or requesting deletion of a missing photo never leaves a target")
    func invalidAndCanceledDeletion() {
        let item = photo("A")
        var state = AlbumViewerState(moments: [item], initialMomentID: item.id)
        state.requestDeletion(id: UUID())
        #expect(state.deleteCandidateID == nil)
        state.requestDeletion(id: item.id)
        state.cancelDeletion()
        #expect(state.takeDeletionCandidate() == nil)
    }

    @Test("Accessible paging stops at either end of the album")
    func boundedPaging() {
        let photos = [photo("A"), photo("B")]
        var state = AlbumViewerState(moments: photos, initialMomentID: photos[0].id)
        state.move(by: -1)
        #expect(state.selectedMomentID == photos[0].id)
        state.move(by: 1)
        #expect(state.selectedMomentID == photos[1].id)
        state.move(by: 1)
        #expect(state.selectedMomentID == photos[1].id)
    }

    private func photo(_ name: String) -> EventMoment {
        EventMoment(imageData: Data([1]), addedBy: name)
    }
}
