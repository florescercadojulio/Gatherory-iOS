import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Gatherory

@MainActor
struct AlbumPresentationTests {
    @Test("Narrow spaces keep two columns regardless of the device")
    func narrowColumns() {
        for width: CGFloat in [320, 393, 430, 590] {
            #expect(AlbumPresentation.columnCount(availableWidth: width) == 2)
        }
    }

    @Test("Even column counts follow available width when the same scene grows and shrinks")
    func resizableColumns() {
        let widths: [CGFloat] = [320, 594, 795, 796, 1024, 1199, 1200, 1366, 800, 430, 320]
        #expect(widths.map { AlbumPresentation.columnCount(availableWidth: $0) } == [2, 2, 2, 4, 4, 4, 6, 6, 4, 2, 2])
        #expect(AlbumPresentation.columnCount(availableWidth: .greatestFiniteMagnitude) == 6)
    }

    @Test("Invalid and unresolved widths use a stable two-column layout")
    func invalidWidths() {
        for width: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            #expect(AlbumPresentation.columnCount(availableWidth: width) == 2)
        }
    }

    @Test("Photo shapes preserve variety while extreme panoramas and portraits stay usable")
    func boundedAspectRatios() {
        #expect(AlbumPresentation.aspectRatio(pixelWidth: 120, pixelHeight: 100) == 1.2)
        #expect(AlbumPresentation.aspectRatio(pixelWidth: 300, pixelHeight: 100) == 1.5)
        #expect(AlbumPresentation.aspectRatio(pixelWidth: 100, pixelHeight: 300) == 0.65)
        for dimensions: (CGFloat, CGFloat) in [(0, 100), (100, 0), (-1, 100), (.nan, 100), (100, .infinity)] {
            #expect(AlbumPresentation.aspectRatio(pixelWidth: dimensions.0, pixelHeight: dimensions.1) == 1)
        }
    }

    @Test("Encoded image metadata respects rotated and mirrored EXIF orientations")
    func imageMetadataOrientation() throws {
        for orientation in 1...8 {
            let data = try imageData(orientation: orientation)
            let expected: CGFloat = orientation >= 5 ? 80.0 / 120.0 : 1.5
            #expect(abs(AlbumPresentation.aspectRatio(imageData: data) - expected) < 0.0001)
        }
    }

    @Test("Missing and corrupt photo data have a stable square placeholder")
    func unavailableImageData() {
        #expect(AlbumPresentation.aspectRatio(imageData: nil) == 1)
        #expect(AlbumPresentation.aspectRatio(imageData: Data()) == 1)
        #expect(AlbumPresentation.aspectRatio(imageData: Data([0, 1, 2, 3])) == 1)
    }

    @Test("Masonry adds each next photo to the shortest column instead of alternating rows")
    func masonryUsesShortestColumn() throws {
        let portrait = EventMoment(imageData: try imageData(width: 80, height: 120), addedBy: "One")
        let landscape = EventMoment(imageData: try imageData(), addedBy: "Two")
        let square = EventMoment(imageData: try imageData(width: 100, height: 100), addedBy: "Three")
        let last = EventMoment(imageData: Data(), addedBy: "Four")
        let columns = AlbumPresentation.columns(
            moments: [portrait, landscape, square, last], count: 2, columnWidth: 100
        )
        #expect(columns.map { $0.map(\.id) } == [[portrait.id, last.id], [landscape.id, square.id]])
    }

    @Test("Masonry preserves every photo exactly once and balances equal-sized cards")
    func masonryPreservesPhotos() {
        let moments = (1...7).map { EventMoment(imageData: Data(), addedBy: "Person \($0)") }
        let columns = AlbumPresentation.columns(moments: moments, count: 3, columnWidth: 190)
        #expect(columns.map(\.count) == [3, 2, 2])
        #expect(columns.flatMap { $0 }.count == moments.count)
        #expect(Set(columns.flatMap { $0 }.map(\.id)) == Set(moments.map(\.id)))
        #expect(columns[0].map(\.id) == [moments[0].id, moments[3].id, moments[6].id])
        #expect(AlbumPresentation.columns(moments: [], count: 4, columnWidth: 190).count == 4)
        #expect(AlbumPresentation.columns(moments: moments, count: 0, columnWidth: .nan) == [moments])
    }

    @Test("Selection toggles individual photos and select-all replaces stale identities")
    func selectionControls() {
        let first = UUID()
        let second = UUID()
        let stale = UUID()
        var selection = AlbumSelection()
        #expect(selection.isEmpty)
        selection.toggle(first)
        #expect(selection.contains(first))
        #expect(selection.count == 1)
        selection.toggle(first)
        #expect(selection.isEmpty)
        selection.toggle(stale)
        selection.selectAll([first, first, second])
        #expect(selection.selectedIDs == [first, second])
        selection.clear()
        #expect(selection.isEmpty)
    }

    @Test("Hidden or removed photos are pruned, and newly available photos are not auto-selected")
    func selectionReconciliation() {
        let first = UUID()
        let removed = UUID()
        let newlyAvailable = UUID()
        var selection = AlbumSelection()
        selection.selectAll([first, removed])
        selection.reconcile(availableIDs: [first, newlyAvailable])
        #expect(selection.selectedIDs == [first])
        selection.reconcile(availableIDs: [])
        #expect(selection.isEmpty)
    }

    @Test("Saving selected photos preserves gallery order and excludes stale photo data")
    func selectedExportOrder() {
        let first = EventMoment(imageData: Data([1]), addedBy: "One")
        let second = EventMoment(imageData: Data([2]), addedBy: "Two")
        let third = EventMoment(imageData: Data([3]), addedBy: "Three")
        var selection = AlbumSelection()
        selection.toggle(third.id)
        selection.toggle(UUID())
        selection.toggle(first.id)
        #expect(selection.selectedMoments(from: [first, second, third]).map(\.id) == [first.id, third.id])
        #expect(selection.selectedMoments(from: [second, third]).map(\.id) == [third.id])
    }

    private func imageData(orientation: Int = 1, width: Int = 120, height: Int = 80) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
