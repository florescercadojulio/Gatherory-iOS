import Testing
@testable import Gatherory

@MainActor
struct BlueprintPreviewPagesTests {
    @Test("Event pages preserve authored order in groups of four, including the partial last page")
    func eventPages() {
        let items = Array(0..<9)
        let pages = BlueprintPreviewPages.events(items)
        #expect(pages == [[0, 1, 2, 3], [4, 5, 6, 7], [8]])
        #expect(pages.flatMap { $0 } == items)
        #expect(BlueprintPreviewPages.events([Int]()).isEmpty)
    }

    @Test("Accessibility event pages keep the same items and order with two single-column rows")
    func accessibleEventPages() {
        #expect(BlueprintPreviewPages.events(Array(0..<5), accessibility: true) == [[0, 1], [2, 3], [4]])
    }

    @Test("Idea columns contain three line items without padding, dropping or duplicating content")
    func ideaPages() {
        let items = Array(0..<8)
        let pages = BlueprintPreviewPages.ideas(items)
        #expect(pages == [[0, 1, 2], [3, 4, 5], [6, 7]])
        #expect(pages.flatMap { $0 } == items)
        #expect(BlueprintPreviewPages.ideas([1]) == [[1]])
        #expect(BlueprintPreviewPages.ideas([Int]()).isEmpty)
    }
}
