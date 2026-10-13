import Foundation
import Testing
@testable import Gatherory

struct CalendarEventTests {
    @Test("Unscheduled events do not create misleading calendar dates")
    func unscheduled() {
        #expect(CalendarEventDraft.make(title: "Dinner", startsAt: nil, endsAt: nil, isAllDay: false, timeZoneIdentifier: "America/Detroit", location: nil, notes: nil) == nil)
    }
    @Test("Timed copies preserve dates and fill a missing or invalid end")
    func timed() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for end in [nil, start, start.addingTimeInterval(-10)] {
            let draft = try #require(CalendarEventDraft.make(title: "Dinner", startsAt: start, endsAt: end, isAllDay: false, timeZoneIdentifier: "America/Detroit", location: "Cabin", notes: "Arrival directions"))
            #expect(draft.endsAt == start.addingTimeInterval(3600))
            #expect(draft.location == "Cabin")
            #expect(draft.notes == "Arrival directions")
        }
    }
    @Test("All-day calendar copies use exclusive ends and respect daylight saving")
    func daylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Detroit"))
        for (month, day, hours) in [(3, 14, 23), (11, 7, 25)] {
            let start = try #require(calendar.date(from: DateComponents(year: 2027, month: month, day: day, hour: 12)))
            let draft = try #require(CalendarEventDraft.make(title: "Gathering", startsAt: start, endsAt: nil, isAllDay: true, timeZoneIdentifier: calendar.timeZone.identifier, location: nil, notes: nil))
            #expect(draft.startsAt == calendar.startOfDay(for: start))
            #expect(draft.endsAt.timeIntervalSince(draft.startsAt) == Double(hours * 3600))
        }
    }
}
