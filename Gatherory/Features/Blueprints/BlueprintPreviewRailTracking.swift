import Foundation
import CoreGraphics

/// Presentation-only tracking; requested scroll targets are not observations of
/// the viewport. Keeping them separate prevents feedback loops during dragging.
struct BlueprintPreviewRailTracking: Equatable {
    private(set) var visibleID: BlueprintPreviewEventID?
    private(set) var scrubbedID: BlueprintPreviewEventID?
    private(set) var requestedID: BlueprintPreviewEventID?

    func selection(fallback: BlueprintPreviewEventID) -> BlueprintPreviewEventID {
        scrubbedID ?? requestedID ?? visibleID ?? fallback
    }

    mutating func observe(_ id: BlueprintPreviewEventID) {
        guard visibleID != id || requestedID == id else { return }
        visibleID = id
        if requestedID == id { requestedID = nil }
    }

    mutating func preview(_ id: BlueprintPreviewEventID) {
        scrubbedID = id
        requestedID = id
    }

    mutating func commit(_ id: BlueprintPreviewEventID) {
        scrubbedID = nil
        requestedID = id == visibleID ? nil : id
    }

    mutating func beginDirectScroll() {
        scrubbedID = nil
        requestedID = nil
    }

    /// Uses actual card positions, including content insets and saved-preview
    /// notices, rather than estimating a page from a fixed-height scroll offset.
    static func centeredID(
        orderedIDs: [BlueprintPreviewEventID],
        frames: [BlueprintPreviewEventID: CGRect],
        viewportHeight: CGFloat
    ) -> BlueprintPreviewEventID? {
        guard viewportHeight.isFinite, viewportHeight > 0 else { return nil }
        let center = viewportHeight / 2
        return orderedIDs.compactMap { id -> (id: BlueprintPreviewEventID, distance: CGFloat)? in
            guard let frame = frames[id], frame.height > 0,
                  frame.minY.isFinite, frame.maxY.isFinite,
                  frame.maxY > 0, frame.minY < viewportHeight else { return nil }
            return (id, abs(frame.midY - center))
        }.min { $0.distance < $1.distance }?.id
    }
}
