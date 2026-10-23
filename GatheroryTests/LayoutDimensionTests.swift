import CoreGraphics
import Testing
@testable import Gatherory

struct LayoutDimensionTests {
    @Test("Artwork and empty-state frame geometry rejects negative, infinite and NaN dimensions")
    func concreteFrameSizes() {
        #expect(LayoutDimensions.size(CGSize(width: 390, height: 844)) == CGSize(width: 390, height: 844))
        #expect(LayoutDimensions.size(CGSize(width: -1, height: CGFloat.infinity)) == .zero)
        #expect(LayoutDimensions.size(CGSize(width: CGFloat.nan, height: -100)) == .zero)
        #expect(LayoutDimensions.size(CGSize(width: 320, height: CGFloat.nan)) == CGSize(width: 320, height: 0))
        #expect(LayoutDimensions.nonnegative(0) == 0)
    }
    @Test("Masonry layout probes produce finite, nonnegative dimensions")
    func finiteLayoutProposals() {
        #expect(MasonryLayout.resolvedWidth(.infinity, idealWidth: 320) == 320)
        #expect(MasonryLayout.resolvedWidth(.nan, idealWidth: 320) == 320)
        #expect(MasonryLayout.resolvedWidth(nil, idealWidth: 320) == 320)
        #expect(MasonryLayout.resolvedWidth(-40, idealWidth: 320) == 0)
        #expect(MasonryLayout.resolvedWidth(390, idealWidth: 320) == 390)
        #expect(MasonryLayout.finiteDimension(.infinity) == 0)
        #expect(MasonryLayout.finiteDimension(.nan) == 0)
        #expect(MasonryLayout.finiteDimension(-1) == 0)
    }

    @Test("Collection columns expand and contract without tiny cards or an odd fold column")
    func resizableCollections() {
        func count(_ width: CGFloat, fallback: Int = 2) -> Int {
            MasonryLayout.adaptiveColumnCount(width: width, fallback: fallback,
                                             minimumColumnWidth: 170, spacing: 12)
        }
        #expect(count(260) == 1)
        #expect(count(342) == 2)
        #expect(count(700) == 2)
        #expect(count(740) == 4)
        #expect(count(1100) == 6)
        #expect(count(342) == 2) // Folding back restores the compact collection.
        #expect(count(1100, fallback: 1) == 1)
        #expect(count(.nan) == 2)
        #expect(count(.infinity) == 2)
        for width in stride(from: CGFloat(300), through: 1600, by: 20) {
            let columns = count(width)
            #expect(columns.isMultiple(of: 2))
            #expect((width - CGFloat(columns - 1) * 12) / CGFloat(columns) >= 140)
        }
    }

    @Test("Event covers adapt to short windows and retain room for accessibility text")
    func resizableEventCovers() {
        #expect(LayoutDimensions.heroHeight(availableHeight: 844, isAccessibilitySize: false) == 640)
        #expect(LayoutDimensions.heroHeight(availableHeight: 540, isAccessibilitySize: false) == 516)
        #expect(LayoutDimensions.heroHeight(availableHeight: 320, isAccessibilitySize: false) == 420)
        #expect(LayoutDimensions.heroHeight(availableHeight: 320, isAccessibilitySize: true) == 640)
        #expect(LayoutDimensions.heroHeight(availableHeight: .nan, isAccessibilitySize: false) == 640)
    }

    @Test("An asymmetric fold remains between collection cards and outside single-card reading")
    func reservedDivisionClearance() {
        let division = LayoutDivision(lowerBound: 450, upperBound: 514)
        let slots = MasonryLayout.columnSlots(width: 1000, count: 4, spacing: 12, division: division)
        #expect(slots.origins.count == 4)
        for x in slots.origins {
            #expect(x >= 0 && x + slots.width <= 1000)
            #expect(x + slots.width <= 450 || x >= 514)
        }
        let reading = MasonryLayout.columnSlots(width: 1000, count: 1, spacing: 12, division: division)
        #expect(reading.origins == [514])
        #expect(reading.width == 486)
        #expect(division.usableRange(in: 1000) == 514...1000)
        let narrowSide = MasonryLayout.columnSlots(width: 800, count: 4, spacing: 12,
                                                  division: LayoutDivision(lowerBound: 200, upperBound: 280))
        #expect(narrowSide.origins.count == 2)
        #expect(narrowSide.width >= 140)
        let unfolded = MasonryLayout.columnSlots(width: 1000, count: 4, spacing: 12, division: nil)
        #expect(unfolded.width == 241)
        #expect(unfolded.origins == [0, 253, 506, 759])
    }
}
