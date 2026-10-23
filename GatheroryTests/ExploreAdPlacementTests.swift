import Foundation
import Testing
@testable import Gatherory

struct ExploreAdPlacementTests {
    @Test("A ready ad waits for a measured viewport and admits only below it")
    func admissionWaitsForSafeAnchor() {
        var state = ExploreAdPlacementState()
        let admissionResult1 = !state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult1)
        #expect(state.skippedSlots.isEmpty)

        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admissionResult2 = state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult2)
        #expect(state.renders(slotID: "slot-6", creativeID: "creative-a"))
        #expect(state.reservedHeight(for: "slot-6") == 280)
    }

    @Test("Crossing the insertion point before first admission skips it for the feed")
    func firstAdmissionIsPermanentlySkippedAfterCrossing() {
        var state = ExploreAdPlacementState()
        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: false)

        let admissionResult3 = !state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult3)
        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admissionResult4 = !state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult4)
        #expect(state.reservedHeight(for: "slot-6") == nil)
    }

    @Test("Unknown or invalid width never latches a slot as skipped")
    func unknownViewportDoesNotSkip() {
        var state = ExploreAdPlacementState()
        state.updateAnchor(slotID: "slot-6", width: .nan, insertionBelowViewport: false)
        #expect(state.anchors["slot-6"] == nil)
        #expect(state.skippedSlots.isEmpty)
        let admissionResult5 = !state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult5)

        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admissionResult6 = state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult6)
    }

    @Test("Malformed creative dimensions and identifiers are rejected")
    func malformedCreativesAreRejected() {
        var state = ExploreAdPlacementState()
        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)

        let admissionResult7 = !state.admit(slotID: "slot-6", creativeID: "creative-a", height: .nan)
        #expect(admissionResult7)
        let admissionResult8 = !state.admit(slotID: "slot-6", creativeID: "creative-a", height: .infinity)
        #expect(admissionResult8)
        let admissionResult9 = !state.admit(slotID: "slot-6", creativeID: "creative-a", height: 0)
        #expect(admissionResult9)
        let admissionResult10 = !state.admit(slotID: "slot-6", creativeID: "", height: 280)
        #expect(admissionResult10)
        #expect(state.reservedHeight(for: "slot-6") == nil)
        #expect(state.skippedSlots.isEmpty)
    }

    @Test("Creative loss preserves geometry and a tall replacement waits for a safe anchor")
    func lossRetainsGeometryUntilTallReplacementIsSafe() {
        var state = ExploreAdPlacementState()
        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admissionResult11 = state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult11)

        state.removeCreative(slotID: "slot-6", creativeID: "creative-a")
        #expect(!state.renders(slotID: "slot-6", creativeID: "creative-a"))
        #expect(state.reservedHeight(for: "slot-6") == 280)

        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: false)
        let admissionResult12 = !state.admit(slotID: "slot-6", creativeID: "creative-b", height: 540)
        #expect(admissionResult12)
        #expect(!state.renders(slotID: "slot-6", creativeID: "creative-b"))
        #expect(state.reservedHeight(for: "slot-6") == 280)

        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admissionResult13 = state.admit(slotID: "slot-6", creativeID: "creative-b", height: 540)
        #expect(admissionResult13)
        #expect(state.renders(slotID: "slot-6", creativeID: "creative-b"))
        #expect(state.reservedHeight(for: "slot-6") == 540)
    }

    @Test("A fitting replacement renders while visible without shrinking reserved height")
    func visibleFittingReplacementKeepsReservedHeight() {
        var state = ExploreAdPlacementState()
        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admissionResult14 = state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult14)
        state.removeCreative(slotID: "slot-6", creativeID: "creative-a")
        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: false)

        let admissionResult15 = state.admit(slotID: "slot-6", creativeID: "creative-b", height: 220)
        #expect(admissionResult15)
        #expect(state.reservedHeight(for: "slot-6") == 280)
        #expect(state.renders(slotID: "slot-6", creativeID: "creative-b"))
    }

    @Test("A changed column width cannot render an old measured creative")
    func changedWidthNeedsNewGeometry() {
        var state = ExploreAdPlacementState()
        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admitted = state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admitted)
        state.updateAnchor(slotID: "slot-6", width: 160, insertionBelowViewport: true)
        #expect(!state.renders(slotID: "slot-6", creativeID: "creative-a"))
        state.reset()
        state.updateAnchor(slotID: "slot-6", width: 160, insertionBelowViewport: true)
        let remeasured = state.admit(slotID: "slot-6", creativeID: "creative-a", height: 540)
        #expect(remeasured)
        #expect(state.reservedHeight(for: "slot-6") == 540)
    }

    @Test("Reset clears anchors, creative identity, retained height, and skipped slots")
    func resetClearsFeedState() {
        var state = ExploreAdPlacementState()
        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admissionResult16 = state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult16)
        state.updateAnchor(slotID: "slot-7", width: 360, insertionBelowViewport: false)
        state.reset()

        #expect(state.anchors.isEmpty)
        #expect(state.placements.isEmpty)
        #expect(state.skippedSlots.isEmpty)
        #expect(!state.renders(slotID: "slot-6", creativeID: "creative-a"))
        #expect(state.reservedHeight(for: "slot-6") == nil)

        state.updateAnchor(slotID: "slot-6", width: 360, insertionBelowViewport: true)
        let admissionResult17 = state.admit(slotID: "slot-6", creativeID: "creative-a", height: 280)
        #expect(admissionResult17)
    }
}
