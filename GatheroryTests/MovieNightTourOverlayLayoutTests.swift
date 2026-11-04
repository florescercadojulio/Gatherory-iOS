import Foundation
import CoreGraphics
import Testing
@testable import Gatherory

@MainActor
struct MovieNightTourOverlayLayoutTests {
    @Test("A side toolbar target stays reachable while the guide fits the content lane")
    func sideToolbarTargetOutsideContentLane() {
        let content = CGRect(x: 0, y: 0, width: 382, height: 606)
        let filter = CGRect(x: 391, y: 180, width: 54, height: 36)
        let placement = MovieNightTourOverlayLayout.place(
            target: filter, viewport: content.insetBy(dx: 12, dy: 12),
            bubbleSize: CGSize(width: 320, height: 200),
            targetViewport: content.union(filter)
        )
        #expect(placement.targetIsVisible)
        #expect(content.contains(placement.bubbleFrame))
        #expect(!placement.bubbleFrame.intersects(filter))
        #expect(placement.pointerEnd.map { filter.insetBy(dx: -1, dy: -1).contains($0) } == true)
    }

    @Test("A toolbar target can sit outside the bubble safe area while its pointer stays on screen")
    func nativeToolbarTargetUsesItsVisibleWindowBounds() {
        let bubbleViewport = CGRect(x: 12, y: 62, width: 378, height: 470)
        let screen = CGRect(x: 0, y: 0, width: 402, height: 673)
        let filter = CGRect(x: 26, y: 0, width: 44, height: 44)
        let placement = MovieNightTourOverlayLayout.place(
            target: filter, viewport: bubbleViewport, bubbleSize: CGSize(width: 320, height: 170),
            targetViewport: screen
        )
        #expect(placement.targetIsVisible)
        #expect(bubbleViewport.contains(placement.bubbleFrame))
        #expect(!placement.bubbleFrame.intersects(filter))
        #expect(placement.pointerEnd.map { filter.insetBy(dx: -1, dy: -1).contains($0) } == true)
    }

    @Test("A visible control gets a pointer and the bubble fits without covering it when room exists")
    func visibleTargetGetsPointerAndClearBubblePlacement() {
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)
        let target = CGRect(x: 140, y: 360, width: 120, height: 60)
        let placement = MovieNightTourOverlayLayout.place(
            target: target,
            viewport: viewport,
            bubbleSize: CGSize(width: 240, height: 120)
        )

        #expect(placement.targetIsVisible)
        #expect(viewport.contains(placement.bubbleFrame))
        #expect(placement.bubbleFrame.intersection(target).isEmpty)
        let pointerStart = placement.pointerStart
        let pointerEnd = placement.pointerEnd
        #expect(pointerStart != nil)
        #expect(pointerEnd != nil)
        if let pointerEnd {
            #expect(target.insetBy(dx: -1, dy: -1).contains(pointerEnd))
        }
    }

    @Test("A target near the bottom places the bubble above it")
    func bottomTargetPlacesBubbleAbove() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 700)
        let target = CGRect(x: 130, y: 610, width: 130, height: 55)
        let placement = MovieNightTourOverlayLayout.place(
            target: target,
            viewport: viewport,
            bubbleSize: CGSize(width: 250, height: 150)
        )

        #expect(placement.targetIsVisible)
        #expect(viewport.contains(placement.bubbleFrame))
        #expect(placement.bubbleFrame.maxY <= target.minY)
        #expect(placement.pointerStart != nil)
        #expect(placement.pointerEnd != nil)
    }

    @Test("A narrow viewport constrains the bubble while retaining its target pointer")
    func narrowViewportConstrainsBubble() {
        let viewport = CGRect(x: 0, y: 0, width: 220, height: 320)
        let target = CGRect(x: 80, y: 150, width: 60, height: 40)
        let placement = MovieNightTourOverlayLayout.place(
            target: target,
            viewport: viewport,
            bubbleSize: CGSize(width: 300, height: 100)
        )

        #expect(placement.targetIsVisible)
        #expect(viewport.contains(placement.bubbleFrame))
        #expect(placement.bubbleFrame.width == viewport.width)
        #expect(placement.pointerStart != nil)
        #expect(placement.pointerEnd != nil)
    }

    @Test("Offscreen and substantially clipped targets do not get pointers")
    func hiddenTargetsUsePointerlessFallback() {
        let viewport = CGRect(x: 0, y: 0, width: 300, height: 500)
        let offscreen = MovieNightTourOverlayLayout.place(
            target: CGRect(x: 320, y: 200, width: 80, height: 50),
            viewport: viewport,
            bubbleSize: CGSize(width: 240, height: 120)
        )
        let clipped = MovieNightTourOverlayLayout.place(
            target: CGRect(x: 285, y: 200, width: 60, height: 50),
            viewport: viewport,
            bubbleSize: CGSize(width: 240, height: 120)
        )

        for placement in [offscreen, clipped] {
            #expect(!placement.targetIsVisible)
            #expect(viewport.contains(placement.bubbleFrame))
            #expect(placement.pointerStart == nil)
            #expect(placement.pointerEnd == nil)
        }
    }

    @Test("A missing target uses a pointerless fallback inside the viewport")
    func missingTargetUsesFallback() {
        let viewport = CGRect(x: 20, y: 40, width: 280, height: 420)
        let placement = MovieNightTourOverlayLayout.place(
            target: nil,
            viewport: viewport,
            bubbleSize: CGSize(width: 240, height: 110)
        )

        #expect(!placement.targetIsVisible)
        #expect(viewport.contains(placement.bubbleFrame))
        #expect(placement.pointerStart == nil)
        #expect(placement.pointerEnd == nil)
    }

    @Test("A large target keeps the pointer inside its exposed measured area")
    func largeTargetPointsAtExposedArea() {
        let viewport = CGRect(x: 0, y: 0, width: 300, height: 600)
        let target = CGRect(x: 20, y: 20, width: 260, height: 540)
        let placement = MovieNightTourOverlayLayout.place(
            target: target,
            viewport: viewport,
            bubbleSize: CGSize(width: 220, height: 180)
        )

        #expect(placement.targetIsVisible)
        #expect(viewport.contains(placement.bubbleFrame))
        let pointerEnd = placement.pointerEnd
        #expect(pointerEnd != nil)
        if let pointerEnd {
            #expect(target.contains(pointerEnd))
            #expect(!placement.bubbleFrame.insetBy(dx: -8, dy: -8).contains(pointerEnd))
        }
    }

    @Test("Zero and nonfinite geometry returns a harmless pointerless placement")
    func invalidGeometryReturnsNoPointer() {
        let zero = MovieNightTourOverlayLayout.place(
            target: CGRect(x: 0, y: 0, width: 0, height: 0),
            viewport: .zero,
            bubbleSize: CGSize(width: 120, height: 60)
        )
        let nonfinite = MovieNightTourOverlayLayout.place(
            target: CGRect(x: CGFloat.nan, y: 10, width: 80, height: 40),
            viewport: CGRect(x: 0, y: 0, width: 300, height: 500),
            bubbleSize: CGSize(width: CGFloat.infinity, height: 60)
        )

        for placement in [zero, nonfinite] {
            #expect(!placement.targetIsVisible)
            #expect(placement.bubbleFrame == .zero)
            #expect(placement.pointerStart == nil)
            #expect(placement.pointerEnd == nil)
        }
    }
}
