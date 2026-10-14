import CoreGraphics
import Testing
@testable import Gatherory

struct LayoutDimensionTests {
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
}
