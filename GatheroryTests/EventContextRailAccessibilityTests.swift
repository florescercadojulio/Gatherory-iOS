import Testing
@testable import Gatherory

@MainActor
struct EventContextRailAccessibilityTests {
    @Test("Compact preview bubbles keep the full event name and schedule available to VoiceOver")
    func compactPreviewContext() {
        let title = "A long ceremony name that must remain available in full"
        let schedule = "Suggested time 12:00 · -30 days from the main event"
        let rail = EventContextRail(
            itemIDs: [0, 1], selectedID: 0, previewIndex: 1,
            title: { $0 == 1 ? title : "Wedding" },
            annotation: { $0 == 1 ? title : "Wedding" },
            onPreview: { _ in }, onCommit: { _ in },
            usesCompactBubble: true, accessibilityAnnotation: { _ in schedule }
        )
        #expect(rail.annotation(1) == title)
        #expect(rail.accessibilityValue == "\(title), 2 of 2, \(schedule)")
    }

    @Test("Existing live rail defaults and empty rail accessibility stay unchanged")
    func liveDefaults() {
        let rail = EventContextRail(
            itemIDs: [0, 1], selectedID: 1, previewIndex: nil,
            title: { _ in "Ceremony" }, annotation: { _ in "Jan 16, 2027" },
            onPreview: { _ in }, onCommit: { _ in }
        )
        #expect(!rail.usesCompactBubble)
        #expect(rail.accessibilityValue == "Ceremony, 2 of 2")
        let empty = EventContextRail<Int>(
            itemIDs: [], selectedID: 0, previewIndex: nil,
            title: { _ in "" }, annotation: { _ in nil },
            onPreview: { _ in }, onCommit: { _ in }
        )
        #expect(empty.accessibilityValue == "No event")
    }
}
