import CoreGraphics
import Foundation
import ImageIO

/// Geometry and selection rules shared by the album's previews and full gallery.
enum AlbumPresentation {
    /// Keep the familiar two-column collage on iPhone. iPad responds to its
    /// actual window width, including narrow Split View and Stage Manager windows.
    static func columnCount(isPad: Bool, availableWidth: CGFloat) -> Int {
        guard isPad, availableWidth.isFinite, availableWidth > 0 else { return 2 }
        let minimumCardWidth: CGFloat = 190
        let spacing: CGFloat = 12
        let count = ((availableWidth + spacing) / (minimumCardWidth + spacing)).rounded(.down)
        return Int(min(6, max(2, count)))
    }

    /// Read encoded dimensions without decoding the full photo into memory.
    static func aspectRatio(imageData: Data?) -> CGFloat {
        guard let imageData, !imageData.isEmpty,
              let source = CGImageSourceCreateWithData(
                imageData as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return 1 }
        return aspectRatio(
            pixelWidth: CGFloat(width.doubleValue),
            pixelHeight: CGFloat(height.doubleValue),
            orientation: (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        )
    }

    static func aspectRatio(pixelWidth: CGFloat, pixelHeight: CGFloat, orientation: Int = 1) -> CGFloat {
        guard pixelWidth.isFinite, pixelHeight.isFinite,
              pixelWidth > 0, pixelHeight > 0 else { return 1 }
        // EXIF 5–8 rotate the display axes, including mirrored orientations.
        let rotated = (5...8).contains(orientation)
        let ratio = rotated ? pixelHeight / pixelWidth : pixelWidth / pixelHeight
        return min(1.5, max(0.65, ratio))
    }

    /// Match the Ideas collage: append the next photo to the shortest column.
    /// Lazy stacks can then defer image decoding until their cards approach view.
    static func columns(
        moments: [EventMoment], count: Int, columnWidth: CGFloat, spacing: CGFloat = 12
    ) -> [[EventMoment]] {
        let columnCount = max(1, count)
        let width = columnWidth.isFinite && columnWidth > 0 ? columnWidth : 190
        let gap = spacing.isFinite ? max(0, spacing) : 12
        var columns = Array(repeating: [EventMoment](), count: columnCount)
        var heights = Array(repeating: CGFloat.zero, count: columnCount)
        for moment in moments {
            // The first shortest column wins ties, keeping placement stable.
            let index = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            columns[index].append(moment)
            heights[index] += width / aspectRatio(imageData: moment.imageData) + gap
        }
        return columns
    }
}

/// Store only identities; saving resolves the current, visible gallery again.
/// This prevents a deleted or personally hidden photo from lingering in a batch.
struct AlbumSelection: Equatable {
    private(set) var selectedIDs: Set<UUID> = []

    var isEmpty: Bool { selectedIDs.isEmpty }
    var count: Int { selectedIDs.count }

    func contains(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    mutating func toggle(_ id: UUID) {
        if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
    }

    mutating func selectAll(_ ids: [UUID]) {
        selectedIDs = Set(ids)
    }

    mutating func clear() {
        selectedIDs.removeAll()
    }

    mutating func reconcile(availableIDs: [UUID]) {
        selectedIDs.formIntersection(availableIDs)
    }

    func selectedMoments(from moments: [EventMoment]) -> [EventMoment] {
        moments.filter { selectedIDs.contains($0.id) }
    }
}
