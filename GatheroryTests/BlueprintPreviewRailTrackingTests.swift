import Foundation
import CoreGraphics
import Testing
@testable import Gatherory

@MainActor
struct BlueprintPreviewRailTrackingTests {
    @Test("The rail follows the actual centered card while scrolling without requesting another scroll")
    func followsViewport() {
        var tracking = BlueprintPreviewRailTracking()
        tracking.observe(.main)
        #expect(tracking.selection(fallback: .main) == .main)
        tracking.observe(.child("ceremony"))
        #expect(tracking.selection(fallback: .main) == .child("ceremony"))
        #expect(tracking.requestedID == nil)
        #expect(tracking.scrubbedID == nil)
    }

    @Test("Scrubbing updates selection immediately and intermediate frames cannot bounce the marker back")
    func scrubAndCommit() {
        var tracking = BlueprintPreviewRailTracking()
        tracking.observe(.main)
        tracking.preview(.child("reception"))
        #expect(tracking.selection(fallback: .main) == .child("reception"))
        tracking.observe(.child("ceremony"))
        #expect(tracking.selection(fallback: .main) == .child("reception"))
        tracking.commit(.child("reception"))
        #expect(tracking.scrubbedID == nil)
        #expect(tracking.selection(fallback: .main) == .child("reception"))
        tracking.observe(.child("reception"))
        #expect(tracking.requestedID == nil)
        #expect(tracking.selection(fallback: .main) == .child("reception"))
        // Repeated geometry observations keep the same haptic trigger identity.
        tracking.observe(.child("reception"))
        #expect(tracking.selection(fallback: .main) == .child("reception"))
    }

    @Test("A direct swipe can interrupt a requested rail scroll")
    func interruptsScrub() {
        var tracking = BlueprintPreviewRailTracking()
        tracking.observe(.main)
        tracking.preview(.child("reception"))
        tracking.commit(.child("reception"))
        tracking.beginDirectScroll()
        tracking.observe(.child("ceremony"))
        #expect(tracking.selection(fallback: .main) == .child("ceremony"))
        #expect(tracking.requestedID == nil)
    }

    @Test("Viewport tracking uses real geometry, ignores offscreen/stale IDs and supports layout insets")
    func realCardGeometry() {
        let ids: [BlueprintPreviewEventID] = [.main, .child("ceremony"), .child("reception")]
        let frames: [BlueprintPreviewEventID: CGRect] = [
            .main: CGRect(x: 16, y: -400, width: 370, height: 640),
            .child("ceremony"): CGRect(x: 16, y: 256, width: 370, height: 640),
            .child("reception"): CGRect(x: 16, y: 912, width: 370, height: 640),
            .child("stale"): CGRect(x: 16, y: 200, width: 370, height: 300)
        ]
        #expect(BlueprintPreviewRailTracking.centeredID(orderedIDs: ids, frames: frames, viewportHeight: 800) == .child("ceremony"))
        #expect(BlueprintPreviewRailTracking.centeredID(orderedIDs: ids, frames: [.main: CGRect(x: 0, y: 120, width: 370, height: 640)], viewportHeight: 800) == .main)
        #expect(BlueprintPreviewRailTracking.centeredID(orderedIDs: ids, frames: frames, viewportHeight: 0) == nil)
        #expect(BlueprintPreviewRailTracking.centeredID(orderedIDs: ids, frames: [:], viewportHeight: 800) == nil)
    }
}
