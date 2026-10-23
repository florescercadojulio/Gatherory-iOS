import Foundation

/// Pure layout state for consent-gated ads in a scrolling Explore feed.
/// Callers reset this state when the feed identity or its measured width changes.
nonisolated struct ExploreAdPlacementState {
    nonisolated struct Anchor: Equatable {
        let width: CGFloat
        let insertionBelowViewport: Bool
    }

    nonisolated struct Placement: Equatable {
        let width: CGFloat
        fileprivate(set) var height: CGFloat
        fileprivate(set) var creativeID: String?
    }

    private(set) var anchors: [String: Anchor] = [:]
    private(set) var placements: [String: Placement] = [:]
    private(set) var skippedSlots: Set<String> = []

    /// Records a slot's current geometry. An invalid width means the viewport
    /// is unknown, so it clears the anchor without permanently skipping the slot.
    mutating func updateAnchor(slotID: String, width: CGFloat, insertionBelowViewport: Bool) {
        guard !slotID.isEmpty else { return }
        guard width.isFinite, width > 0 else {
            anchors.removeValue(forKey: slotID)
            return
        }

        let anchor = Anchor(width: width, insertionBelowViewport: insertionBelowViewport)
        anchors[slotID] = anchor
        if placements[slotID] == nil, !insertionBelowViewport {
            skippedSlots.insert(slotID)
        }
    }

    /// Admits new creatives below the viewport. A fitting replacement can fill
    /// an existing visible reservation; a taller one waits until the slot is
    /// below the viewport before growing it.
    @discardableResult
    mutating func admit(slotID: String, creativeID: String, height: CGFloat) -> Bool {
        guard !slotID.isEmpty, !creativeID.isEmpty, height.isFinite, height > 0,
              !skippedSlots.contains(slotID),
              let anchor = anchors[slotID] else { return false }

        guard var placement = placements[slotID] else {
            guard anchor.insertionBelowViewport else {
                skippedSlots.insert(slotID)
                return false
            }
            placements[slotID] = Placement(
                width: anchor.width,
                height: height,
                creativeID: creativeID
            )
            return true
        }
        guard placement.width == anchor.width else { return false }
        if height > placement.height, !anchor.insertionBelowViewport {
            return false
        }
        if height > placement.height {
            placement.height = height
        }
        placement.creativeID = creativeID
        placements[slotID] = placement
        return true
    }

    /// Removes the rendered creative while retaining its reserved geometry.
    mutating func removeCreative(slotID: String, creativeID: String) {
        guard var placement = placements[slotID], placement.creativeID == creativeID else { return }
        placement.creativeID = nil
        placements[slotID] = placement
    }

    func renders(slotID: String, creativeID: String) -> Bool {
        guard let placement = placements[slotID], let anchor = anchors[slotID] else { return false }
        return placement.width == anchor.width && placement.creativeID == creativeID
    }

    func reservedHeight(for slotID: String) -> CGFloat? {
        placements[slotID]?.height
    }

    mutating func reset() {
        anchors.removeAll()
        placements.removeAll()
        skippedSlots.removeAll()
    }
}
